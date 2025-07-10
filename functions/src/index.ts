/* eslint-disable max-len */
import * as admin from "firebase-admin";
import {tmpdir} from "os";
import {join} from "path";
import {existsSync, unlinkSync} from "fs";
import {Storage} from "@google-cloud/storage";
import ffmpeg from "fluent-ffmpeg";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import {onObjectFinalized, StorageObjectData} from "firebase-functions/v2/storage";
import {CloudEvent} from "firebase-functions/v2";

admin.initializeApp();
const storage = new Storage();
const firestore = admin.firestore();
ffmpeg.setFfmpegPath(ffmpegInstaller.path);

export const optimizeMp4Video = onObjectFinalized(
  {
    region: "europe-west1",
    memory: "2GiB",
    timeoutSeconds: 540,
  },
  async (event: CloudEvent<StorageObjectData>) => {
    const object = event.data;
    const fileBucket = object.bucket;
    const filePath = object.name || "";
    const contentType = object.contentType || "";
    const fileName = filePath.split("/").pop() || "";
    const videoId = fileName.split(".")[0];
    const videoRef = firestore.collection("videos").doc(videoId);

    console.log("🎯 Déclenchement pour :", filePath);

    if (
      !filePath.startsWith("videos/") ||
      !filePath.endsWith(".mp4") ||
      !contentType.startsWith("video/")
    ) {
      console.log("⛔️ Ignoré (pas une vidéo MP4 valide)");
      return;
    }

    // Vérifie si déjà optimisé
    const docSnap = await videoRef.get();
    if (docSnap.exists && docSnap.data()?.optimized === true) {
      console.log("⚠️ Vidéo déjà optimisée, sortie.");
      return;
    }

    const bucket = storage.bucket(fileBucket);
    const tempInputFile = join(tmpdir(), fileName);
    const optimizedFile = join(tmpdir(), `optimized_${fileName}`);

    try {
      console.log("⬇️ Téléchargement...");
      await bucket.file(filePath).download({destination: tempInputFile});

      // Petite pause pour stabilité I/O
      await new Promise((res) => setTimeout(res, 200));

      console.log("🎬 Compression...");
      await new Promise<void>((resolve, reject) => {
        ffmpeg(tempInputFile)
          .outputOptions([
            "-c:v libx264",
            "-profile:v main",
            "-preset veryfast",
            "-crf 23",
            "-movflags +faststart",
            "-vf scale='min(854,iw)':'-2'",
            "-g 30",
            "-keyint_min 30",
            "-maxrate 1M",
            "-bufsize 2M",
            "-c:a aac",
            "-b:a 96k",
          ])
          .on("end", () => resolve())
          .on("error", (err) => reject(err))
          .save(optimizedFile);
      });

      console.log("⬆️ Upload optimisé...");
      await bucket.upload(optimizedFile, {
        destination: filePath,
        metadata: {
          contentType: "video/mp4",
          cacheControl: "public,max-age=86400",
        },
      });

      await videoRef.set(
        {
          status: "ready",
          optimized: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      console.log("✅ Terminé & Firestore mis à jour.");
    } catch (error) {
      console.error("❌ Erreur :", (error as Error).message);
      await videoRef.set(
        {
          status: "error",
          optimized: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    } finally {
      [tempInputFile, optimizedFile].forEach((file) => {
        if (existsSync(file)) {
          try {
            unlinkSync(file);
            console.log("🧹 Fichier supprimé :", file);
          } catch (e) {
            console.warn("⚠️ Erreur suppression :", (e as Error).message);
          }
        }
      });
    }

    return null;
  }
);
