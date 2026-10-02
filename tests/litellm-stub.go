// AWCEX5Z: disposable loopback-only protocol fixture, never a real provider.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
)

const model = "hestia-opaque-model-7e4/sub:exact"

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
		if !auth {
			fmt.Fprintf(log, "%s %s auth=false\n", r.Method, r.URL.Path)
			http.Error(w, "fake auth required", http.StatusUnauthorized)
			return
		}
		if r.Method == "GET" {
			fmt.Fprintf(log, "GET %s auth=true\n", r.URL.Path)
			w.Header().Set("Content-Type", "application/json")
			if r.URL.Path == "/model_group/info" {
				io.WriteString(w, `{"data":[{"model_group":"`+model+`","providers":["hestia"],"max_input_tokens":8192,"max_output_tokens":256,"supports_vision":false,"supports_reasoning":false,"supports_function_calling":false}]}`)
			} else if r.URL.Path == "/v1/models" {
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
		fmt.Fprintf(log, "POST %s model=%t auth=%t tools=%d stream=%t\n", r.URL.Path, exact, auth, len(request.Tools), request.Stream)
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
