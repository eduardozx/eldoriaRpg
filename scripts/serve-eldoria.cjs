const { createReadStream, statSync } = require("node:fs")
const { createServer } = require("node:http")
const { extname, resolve, sep } = require("node:path")

const root = resolve(process.argv[2] || "/srv/eldoria")
const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".wasm": "application/wasm",
}

createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname)
  const freshPath = pathname.startsWith("/fresh/")
    ? pathname.slice("/fresh".length)
    : pathname
  const filePath = resolve(root, `.${freshPath === "/" ? "/Eldoria.html" : freshPath}`)

  try {
    if (filePath !== root && !filePath.startsWith(`${root}${sep}`)) {
      throw new Error("Path outside web root")
    }
    const stat = statSync(filePath)
    if (!stat.isFile()) throw new Error("Not a file")

    response.writeHead(200, {
      "Content-Type": mimeTypes[extname(filePath)] || "application/octet-stream",
      "Content-Length": stat.size,
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
      "Cross-Origin-Resource-Policy": "same-origin",
      "Cache-Control": "no-store",
    })
    if (request.method === "HEAD") {
      response.end()
      return
    }
    createReadStream(filePath).pipe(response)
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" })
    response.end("Not found")
  }
}).listen(8000, "0.0.0.0")
