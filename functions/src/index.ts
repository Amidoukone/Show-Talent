/* eslint-disable object-curly-spacing */
/* eslint-disable max-len */
import * as admin from "firebase-admin";
import { tmpdir } from "os";
import { join } from "path";
import { mkdirSync, readdirSync, unlinkSync, existsSync } from "fs";
import { Storage } from "@google-cloud/storage";
import ffmpeg from "fluent-ffmpeg";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";
import { onObjectFinalized, StorageObjectData } from "firebase-functions/v2/storage";
import { CloudEvent } from "firebase-functions/v2";

admin.initializeApp();
const storage = new Storage();
const firestore = admin.firestore();

ffmpeg.setFfmpegPath(ffmpegInstaller.path);

export const convertToHLS = onObjectFinalized({
  region: "europe-west1",
  memory: "2GiB",
  timeoutSeconds: 540,
}, async (event: CloudEvent<StorageObjectData>) => {
  const object = event.data;
  const fileBucket = object.bucket;
  const filePath = object.name || "";
  const contentType = object.contentType || "";
  const fileName = filePath.split("/").pop() || "";
  const videoId = fileName.split(".")[0];
  const videoRef = firestore.collection("videos").doc(videoId);

  console.log("⚙️ Fonction déclenchée pour :", filePath);

  if (!filePath.startsWith("videos/") || !filePath.endsWith(".mp4") || !contentType.startsWith("video/")) {
    console.log("⛔️ Fichier ignoré (mauvais chemin ou type).", { filePath, contentType });
    return;
  }

  const bucket = storage.bucket(fileBucket);
  const tempLocalFile = join(tmpdir(), fileName);
  const localHLSDir = join(tmpdir(), `hls_${Date.now()}`);
  const hlsOutput = join(localHLSDir, "index.m3u8");

  mkdirSync(localHLSDir, { recursive: true });

  try {
    console.log("⬇️ Téléchargement de la vidéo...");
    await bucket.file(filePath).download({ destination: tempLocalFile });
    console.log("✅ Téléchargement terminé :", tempLocalFile);

    console.log("🎬 Démarrage conversion FFmpeg...");
    await new Promise<void>((resolve, reject) => {
      ffmpeg(tempLocalFile)
        .addOptions([
          "-profile:v baseline",
          "-level 3.0",
          "-start_number 0",
          "-hls_time 4",
          "-hls_list_size 0",
          "-force_key_frames expr:gte(t,n_forced*4)",
          "-vf scale=w=720:h=1280:force_original_aspect_ratio=decrease",
          "-f hls",
        ])
        .outputOptions("-hls_segment_filename", join(localHLSDir, "segment_%03d.ts"))
        .output(hlsOutput)
        .on("end", () => resolve())
        .on("error", (err) => reject(err))
        .run();
    });

    console.log("✅ Conversion HLS terminée.");

    const hlsFiles = readdirSync(localHLSDir);
    const tsSegments = hlsFiles.filter((f) => f.endsWith(".ts"));
    const m3u8Files = hlsFiles.filter((f) => f.endsWith(".m3u8"));

    if (tsSegments.length === 0 || m3u8Files.length === 0) {
      throw new Error("❌ Aucun fichier HLS valide généré.");
    }

    const hlsStorageDir = `videos/${videoId}`;
    console.log("⬆️ Envoi des segments HLS...");

    await Promise.all(
      hlsFiles.map(async (file) => {
        const localPath = join(localHLSDir, file);
        await bucket.upload(localPath, {
          destination: `${hlsStorageDir}/${file}`,
          metadata: {
            contentType: file.endsWith(".m3u8") ? "application/vnd.apple.mpegurl" : "video/MP2T",
            cacheControl: "public,max-age=86400",
          },
        });
        unlinkSync(localPath);
      })
    );

    console.log("✅ Segments uploadés.");

    const finalM3U8Path = `${hlsStorageDir}/index.m3u8`;
    const [signedUrl] = await bucket.file(finalM3U8Path).getSignedUrl({
      action: "read",
      expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
    });

    const updatePayload = {
      hlsUrl: signedUrl + `?t=${Date.now()}`, // Force un lien unique à chaque fois
      status: "ready",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    console.log("🔐 URL HLS signée :", updatePayload.hlsUrl);

    await videoRef.set(updatePayload, { merge: true });

    console.log("📦 Firestore mis à jour (ready).");

    await bucket.file(filePath).delete().catch((err) => {
      console.warn("⚠️ Suppression de l'original échouée :", (err as Error).message);
    });

    console.log("🧹 Nettoyage terminé pour :", videoId);
  } catch (error) {
    console.error("❌ Erreur HLS:", (error as Error).message || error);
    await videoRef.set({
      status: "error",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } finally {
    if (existsSync(tempLocalFile)) {
      try {
        unlinkSync(tempLocalFile);
        console.log("🧽 Temp local supprimé.");
      } catch (err) {
        console.warn("⚠️ Problème suppression temporaire :", (err as Error).message || err);
      }
    }
  }

  return null;
});
