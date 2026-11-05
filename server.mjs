import { createServer } from "node:http"
import path from "node:path"
import { FileFinder } from "@ff-labs/fff-node"

const result = FileFinder.create({
  basePath: path.resolve(process.argv[2] ?? process.cwd()),
  aiMode: true,
  disableMmapCache: true,
  disableContentIndexing: true,
})

if (!result.ok) throw new Error(result.error)

const finder = result.value
await finder.waitForScan(30_000)

const server = createServer((request, response) => {
  const handle = async () => {
    if (request.method !== "POST" || request.url !== "/search") {
      response.writeHead(404).end()
      return
    }

    const chunks = []
    for await (const chunk of request) chunks.push(chunk)
    const input = JSON.parse(Buffer.concat(chunks).toString("utf8"))
    if (input === null || typeof input.query !== "string") {
      response.writeHead(400).end("Expected a query string")
      return
    }

    const found = finder.mixedSearch(input.query.trim(), {
      pageIndex: 0,
      pageSize: 15,
    })
    if (!found.ok) throw new Error(found.error)

    response.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" })
    response.end(
      found.value.items
        .map((entry) => {
          const relative = entry.item.relativePath
          return entry.type === "directory" ? relative.replace(/\/?$/, "/") : relative
        })
        .join("\n"),
    )
  }

  handle().catch((error) => {
    console.error(error)
    response.writeHead(500).end("Search failed")
  })
})

server.on("error", (error) => {
  console.error(error)
  finder.destroy()
  process.exit(1)
})

server.listen(43871, "127.0.0.1", () => {
  console.error("FFF search ready on http://127.0.0.1:43871")
})

const shutdown = () => {
  server.close(() => {
    finder.destroy()
    process.exit(0)
  })
}

process.once("SIGINT", shutdown)
process.once("SIGTERM", shutdown)
