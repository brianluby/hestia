// AWCEX5Z: disposable loopback-only protocol fixture, never a real provider.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"regexp"
)

const model = "hestia-opaque-model-7e4/sub:exact"
const expectedTrace = "11111111-2222-4333-8444-555555555555"

var uuidPattern = regexp.MustCompile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

// main serves a disposable loopback protocol fixture and logs assertions only.
func main() {
	log, err := os.Create("/tmp/hestia-litellm-stub.log")
	if err != nil {
		panic(err)
	}
	defer log.Close()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	port := fmt.Sprint(listener.Addr().(*net.TCPAddr).Port)
	if err := os.WriteFile("/tmp/hestia-litellm-stub.port", []byte(port), 0600); err != nil {
		panic(err)
	}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Record only assertions and routes, never header values or prompts.
		auth := r.Header.Get("Authorization") == "Bearer HESTIA_FAKE_LITELLM_KEY"
		trace := r.Header.Get("x-litellm-trace-id")
		traceExact := trace == expectedTrace
		if !uuidPattern.MatchString(trace) {
			fmt.Fprintf(log, "%s %s auth=%t trace=false\n", r.Method, r.URL.Path, auth)
			http.Error(w, "valid trace header required", http.StatusBadRequest)
			return
		}
		if !auth {
			fmt.Fprintf(log, "%s %s auth=false trace=true traceExact=%t\n", r.Method, r.URL.Path, traceExact)
			http.Error(w, "fake auth required", http.StatusUnauthorized)
			return
		}
		if r.Method == "GET" {
			fmt.Fprintf(log, "GET %s auth=true trace=true traceExact=%t\n", r.URL.Path, traceExact)
			w.Header().Set("Content-Type", "application/json")
			if r.URL.Path == "/v1/models" {
				io.WriteString(w, `{"object":"list","data":[{"id":"`+model+`","object":"model"}]}`)
			} else {
				w.WriteHeader(http.StatusNotFound)
				io.WriteString(w, `{}`)
			}
			return
		}
		if r.Method != "POST" || r.URL.Path != "/v1/chat/completions" {
			http.NotFound(w, r)
			return
		}
		var request struct {
			Model  string            `json:"model"`
			Tools  []json.RawMessage `json:"tools"`
			Stream bool              `json:"stream"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&request); err != nil {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		exact := request.Model == model
		fmt.Fprintf(log, "POST %s model=%t auth=%t trace=true traceExact=%t tools=%d stream=%t\n", r.URL.Path, exact, auth, traceExact, len(request.Tools), request.Stream)
		if !exact || len(request.Tools) != 0 || !request.Stream {
			http.Error(w, "unexpected native request", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		io.WriteString(w, `data: {"id":"hestia-local","object":"chat.completion.chunk","created":1,"model":"`+model+`","choices":[{"index":0,"delta":{"role":"assistant","content":"HESTIA_LOCAL_STUB_OK"},"finish_reason":null}]}`+"\n\n")
		io.WriteString(w, `data: {"id":"hestia-local","object":"chat.completion.chunk","created":1,"model":"`+model+`","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}`+"\n\ndata: [DONE]\n\n")
	})
	if err := http.Serve(listener, handler); err != nil {
		panic(err)
	}
}
