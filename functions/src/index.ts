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

// Initialiser Firebase Admin et Storage
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
    console.log("⛔️ Fichier ignoré (mauvais chemin ou type).");
    return;
  }

  const bucket = storage.bucket(fileBucket);
  const tempLocalFile = join(tmpdir(), fileName);
  const localHLSDir = join(tmpdir(), `hls_${Date.now()}`);
  const hlsOutput = join(localHLSDir, "index.m3u8");

  mkdirSync(localHLSDir, { recursive: true });

  try {
    console.log("⬇️ Téléchargement de la vidéo depuis GCS...");
    await bucket.file(filePath).download({ destination: tempLocalFile });
    console.log("✅ Vidéo téléchargée localement :", tempLocalFile);

    console.log("🔄 Lancement de la conversion HLS...");
    await new Promise<void>((resolve, reject) => {
      ffmpeg(tempLocalFile)
        .addOptions([
          "-profile:v baseline",
          "-level 3.0",
          "-start_number 0",
          "-hls_time 4", // Petits segments = meilleure fluidité
          "-hls_list_size 0",
          "-force_key_frames expr:gte(t,n_forced*4)",
          "-vf scale=w=720:h=1280:force_original_aspect_ratio=decrease", // ✅ scale appliqué CORRECTEMENT
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
      throw new Error("❌ Conversion invalide : Aucun segment .ts ou fichier index.m3u8 trouvé.");
    }

    const hlsStorageDir = `videos/${videoId}`;
    console.log("⬆️ Téléversement des segments...");

    await Promise.all(
      hlsFiles.map(async (file) => {
        const localPath = join(localHLSDir, file);
        await bucket.upload(localPath, {
          destination: `${hlsStorageDir}/${file}`,
          metadata: {
            contentType: file.endsWith(".m3u8") ? "application/vnd.apple.mpegurl" : "video/MP2T",
          },
        });
        unlinkSync(localPath);
      })
    );

    console.log("✅ Segments HLS uploadés.");

    const hlsUrl = `https://storage.googleapis.com/${fileBucket}/${hlsStorageDir}/index.m3u8`;
    console.log("🌍 HLS Public URL:", hlsUrl);

    console.log("📦 Mise à jour Firestore...");
    await videoRef.set({
      hlsUrl: hlsUrl,
      status: "ready",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log("🎯 Document Firestore mis à jour avec status 'ready'.");

    await bucket.file(filePath).delete().catch((err) => {
      console.warn("⚠️ Suppression du fichier original échouée:", (err as Error).message || err);
    });

    console.log("✅ Nettoyage terminé pour :", videoId);
  } catch (error) {
    console.error("❌ Erreur globale :", (error as Error).message || error);
    await videoRef.set({
      status: "error",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } finally {
    if (existsSync(tempLocalFile)) {
      try {
        unlinkSync(tempLocalFile);
        console.log("🧹 Fichier temporaire local supprimé.");
      } catch (err) {
        console.warn("⚠️ Problème de suppression fichier local :", (err as Error).message || err);
      }
    }
  }

  return null;
});
