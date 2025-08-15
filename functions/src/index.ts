/* eslint-disable eol-last */
/* eslint-disable linebreak-style */
/* eslint-disable max-len */

import {tmpdir} from "os";
import {join} from "path";
import {existsSync, unlinkSync} from "fs";
import {Storage} from "@google-cloud/storage";
import ffmpeg from "fluent-ffmpeg";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import {onObjectFinalized, StorageObjectData} from "firebase-functions/v2/storage";
import {CloudEvent} from "firebase-functions/v2";

// ✅ Imports Admin centralisés
import {db, fieldValue} from "./firebase";

// Uniformise la région (mets "europe-west1" si c'est ta région préférée)
const REGION = "europe-west1";

// Configuration FFMPEG
ffmpeg.setFfmpegPath(ffmpegInstaller.path);
const storage = new Storage(); // accès direct au bucket

/**
 * Optimise une vidéo MP4 uploadée dans "videos/"
 */
export const optimizeMp4Video = onObjectFinalized(
  {
    region: REGION,
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
    const videoRef = db.collection("videos").doc(videoId);

    console.log("🎯 Déclenchement pour :", filePath);

    // Filtre strict : on ne traite que les MP4 dans le dossier videos/
    if (
      !filePath.startsWith("videos/") ||
      !filePath.endsWith(".mp4") ||
      !contentType.startsWith("video/")
    ) {
      console.log("⛔️ Ignoré (pas une vidéo MP4 valide)");
      return;
    }

    const bucket = storage.bucket(fileBucket);
    const tempInputFile = join(tmpdir(), fileName);
    const optimizedFile = join(tmpdir(), `optimized_${fileName}`);

    try {
      console.log("⬇️ Téléchargement...");
      await bucket.file(filePath).download({destination: tempInputFile});

      // Petite pause I/O pour stabilité
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

      console.log("⬆️ Upload optimisé (remplacement du fichier d'origine)...");
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
          updatedAt: fieldValue.serverTimestamp(),
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
          updatedAt: fieldValue.serverTimestamp(),
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


// ✅ Fonctions déjà présentes dans ton projet
export {sendVerificationReminder} from "./reminder";
export {cleanupUnverifiedUsers} from "./cleanup";

