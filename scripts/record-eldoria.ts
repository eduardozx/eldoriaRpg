import { mkdir } from "node:fs/promises"
import { resolve } from "node:path"

import {
  createDesktopSandbox,
  saveDesktopArtifact,
} from "/code/harft/tooling/desktop-sandbox/src/index.ts"

const projectRoot = resolve(import.meta.dir, "..")
const artifactsDirectory = resolve(projectRoot, "artifacts")
const videoPath = resolve(artifactsDirectory, "eldoria-gameplay.mp4")
const screenshotPath = resolve(artifactsDirectory, "eldoria-gameplay.png")
const beforeMovementPath = resolve(
  artifactsDirectory,
  "eldoria-before-movement.png"
)
const failurePath = resolve(artifactsDirectory, "eldoria-failure.png")
const gameUrl =
  "http://127.0.0.1:8000/fresh/Eldoria.html?ws=ws%3A%2F%2F172.17.0.1%3A9080"
const localProxySource = `
const http = require("node:http");
http.createServer((request, response) => {
  const upstream = http.request({
    hostname: "172.17.0.1",
    port: 8000,
    path: request.url,
    method: request.method,
    headers: request.headers,
  }, (incoming) => {
    response.writeHead(incoming.statusCode || 502, {
      ...incoming.headers,
      "cross-origin-opener-policy": "same-origin",
      "cross-origin-embedder-policy": "require-corp",
      "cross-origin-resource-policy": "same-origin",
    });
    incoming.pipe(response);
  });
  upstream.on("error", (error) => {
    response.writeHead(502, { "content-type": "text/plain" });
    response.end(error.message);
  });
  request.pipe(upstream);
}).listen(8000, "127.0.0.1");
`

async function command(args: string[]): Promise<void> {
  const process = Bun.spawn({ cmd: args, stdout: "pipe", stderr: "pipe" })
  const [exitCode, stdout, stderr] = await Promise.all([
    process.exited,
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
  ])
  if (exitCode !== 0) {
    throw new Error(`${args[0]} failed: ${stderr || stdout}`)
  }
}

async function run(): Promise<void> {
  await mkdir(artifactsDirectory, { recursive: true })

  const sandbox = await createDesktopSandbox({
    target: "local",
    resolution: { width: 1440, height: 900 },
    controlDaemon: true,
  })
  let recording = false

  try {
    console.log("Starting the localhost web proxy inside the disposable desktop")
    await command([
      "docker",
      "exec",
      "--detach",
      sandbox.id,
      "node",
      "-e",
      localProxySource,
    ])

    console.log("Loading Eldoria in the isolated Chromium desktop")
    await command([
      "docker",
      "exec",
      "--detach",
      "--env",
      "DISPLAY=:0",
      sandbox.id,
      "chromium",
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--no-first-run",
      "--start-maximized",
      "--remote-debugging-address=127.0.0.1",
      "--remote-debugging-port=9222",
      "--remote-allow-origins=*",
      "--enable-webgl",
      "--ignore-gpu-blocklist",
      "--enable-unsafe-swiftshader",
      "--use-gl=angle",
      "--use-angle=swiftshader",
      gameUrl,
    ])
    await sandbox.wait(10_000)

    await sandbox.startRecording({
      profile: "high",
      frameRate: 15,
      maxDurationMs: 90_000,
      maxFileSizeMb: 64,
    })
    recording = true

    console.log("Signing in and entering the game world")
    await sandbox.typeText("Aventureiro", { delayMs: 90 })
    await sandbox.wait(800)
    await sandbox.press("Return")
    await sandbox.wait(7_000)

    console.log("Demonstrating combat, inventory, chat, and movement")
    await sandbox.click({ x: 760, y: 470 })
    await sandbox.wait(600)
    await sandbox.press("space")
    await sandbox.wait(700)
    await sandbox.press("space")
    await sandbox.wait(900)

    await sandbox.press("i")
    await sandbox.wait(2_500)
    await sandbox.press("i")
    await sandbox.wait(700)

    await sandbox.press("Return")
    await sandbox.wait(400)
    await sandbox.typeText("Ola, Eldoria!", { delayMs: 70 })
    await sandbox.press("Return")
    await sandbox.wait(2_500)

    const beforeMovement = await sandbox.captureScreenshot({ format: "png" })
    await saveDesktopArtifact(beforeMovement, beforeMovementPath)

    await command([
      "docker",
      "exec",
      "--env",
      "DISPLAY=:0",
      sandbox.id,
      "xdotool",
      "keydown",
      "d",
    ])
    await sandbox.wait(1_600)
    await command([
      "docker",
      "exec",
      "--env",
      "DISPLAY=:0",
      sandbox.id,
      "xdotool",
      "keyup",
      "d",
    ])
    await sandbox.wait(700)
    await command([
      "docker",
      "exec",
      "--env",
      "DISPLAY=:0",
      sandbox.id,
      "xdotool",
      "keydown",
      "s",
    ])
    await sandbox.wait(1_200)
    await command([
      "docker",
      "exec",
      "--env",
      "DISPLAY=:0",
      sandbox.id,
      "xdotool",
      "keyup",
      "s",
    ])
    await sandbox.wait(1_500)

    const screenshot = await sandbox.captureScreenshot({ format: "png" })
    await saveDesktopArtifact(screenshot, screenshotPath)

    const video = await sandbox.stopRecording()
    recording = false
    await saveDesktopArtifact(video, videoPath)

    console.log(`Saved ${videoPath}`)
    console.log(`Saved ${screenshotPath}`)
  } catch (error) {
    const screenshot = await sandbox.captureScreenshot({ format: "png" })
    await saveDesktopArtifact(screenshot, failurePath)
    if (recording) {
      const video = await sandbox.stopRecording()
      recording = false
      await saveDesktopArtifact(video, resolve(artifactsDirectory, "eldoria-partial.mp4"))
    }
    throw error
  } finally {
    await sandbox.close()
  }
}

await run()
