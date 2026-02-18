package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintf(w, `<!DOCTYPE html>
<html>
<head><title>Demo</title>
<style>
  body { font-family: system-ui; max-width: 600px; margin: 40px auto; padding: 0 20px; background: #f5f5f5; }
  h1 { color: #333; }
  .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin: 16px 0; }
  code { background: #eee; padding: 2px 6px; border-radius: 4px; }
  a { color: #667eea; }
</style>
</head>
<body>
  <h1>HTTPS Toolkit Demo</h1>
  <div class="card">
    <p>This is a demo Go service running behind the HTTPS gateway.</p>
    <p>Try these endpoints:</p>
    <ul>
      <li><a href="health">/health</a> — health check</li>
      <li><a href="api/info">/api/info</a> — service info (JSON)</li>
      <li><a href="api/time">/api/time</a> — current time (JSON)</li>
    </ul>
  </div>
</body>
</html>`)
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "OK")
	})

	mux.HandleFunc("/api/info", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"name":    "https-toolkit-demo",
			"version": "1.0.0",
			"port":    port,
		})
	})

	mux.HandleFunc("/api/time", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"time": time.Now().Format(time.RFC3339),
			"zone": time.Now().Location().String(),
		})
	})

	fmt.Printf("Demo server listening on :%s\n", port)
	http.ListenAndServe(":"+port, mux)
}
