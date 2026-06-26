// Simple HTTPS server using Go crypto/tls (not OpenSSL).
// Used to validate NetObserv GoTLS plaintext capture (--enable_gotls).
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"os"
	"strings"
	"time"
)

var fakeRequestHeaderKeys = []string{
	"Authorization",
	"X-Fake-Trace-Id",
	"X-Fake-Tenant",
	"X-NetObserv-Client",
	"Content-Type",
	"User-Agent",
}

func main() {
	addr := envOr("LISTEN_ADDR", ":8443")
	cert, err := generateSelfSignedCert()
	if err != nil {
		log.Fatalf("cert: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/message", handleMessage)
	mux.HandleFunc("/api/items", handleAPIItems)
	mux.HandleFunc("/api/echo", handleAPIEcho)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok\n"))
	})

	srv := &http.Server{
		Addr:    addr,
		Handler: mux,
		TLSConfig: &tls.Config{
			Certificates: []tls.Certificate{cert},
			MinVersion:   tls.VersionTLS12,
			// Force HTTP/1.1 only. curl/kubelet may negotiate h2; this test server
			// targets GoTLS writeRecordLocked hooks on plain HTTP/1.1 responses.
			NextProtos: []string{"http/1.1"},
		},
	}
	// net/http enables HTTP/2 for TLS by default; an empty map disables it.
	srv.TLSNextProto = map[string]func(*http.Server, *tls.Conn, http.Handler){}

	log.Printf("listening on %s (Go crypto/tls, PID %d)", addr, os.Getpid())
	log.Fatal(srv.ListenAndServeTLS("", ""))
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	setFakeResponseHeaders(w, r, "root", "gotls")
	writePlaintext(w, fmt.Sprintf(
		"NETOBSERV-GOTLS plaintext probe\nTLS stack: Go crypto/tls (writeRecordLocked)\nWorkload: gotls-test-pod\nEndpoint: GET /\nseq=%s time=%s\n",
		r.URL.Query().Get("seq"), time.Now().UTC().Format(time.RFC3339Nano),
	))
}

func handleMessage(w http.ResponseWriter, r *http.Request) {
	setFakeResponseHeaders(w, r, "message", "gotls")
	writePlaintext(w, fmt.Sprintf(
		"NETOBSERV-GOTLS plaintext probe\nTLS stack: Go crypto/tls (writeRecordLocked)\nWorkload: gotls-test-pod\nEndpoint: GET /message\nCapture hint: look for \"NETOBSERV-GOTLS\" in PlaintextPreview\nseq=%s time=%s\n",
		r.URL.Query().Get("seq"), time.Now().UTC().Format(time.RFC3339Nano),
	))
}

func handleAPIItems(w http.ResponseWriter, r *http.Request) {
	setFakeResponseHeaders(w, r, "api-items", "gotls")
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"source":  "gotls",
		"message": "NETOBSERV-GOTLS api/items",
		"items": []map[string]any{
			{"id": 1, "sku": "gotls-epsilon"},
			{"id": 2, "sku": "gotls-zeta"},
		},
		"stack": "go crypto/tls",
		"seq":   r.URL.Query().Get("seq"),
		"time":  time.Now().UTC().Format(time.RFC3339Nano),
	})
}

func handleAPIEcho(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(io.LimitReader(r.Body, 4096))
	clientMsg := string(body)
	if clientMsg == "" {
		clientMsg = "(empty body)"
	}
	setFakeResponseHeaders(w, r, "api-echo", "gotls")
	writePlaintext(w, fmt.Sprintf(
		"NETOBSERV-GOTLS POST echo response\nTLS stack: Go crypto/tls (writeRecordLocked)\nWorkload: gotls-test-pod\nEndpoint: POST /api/echo\nclient_request=%q\nreceived_request_headers:\n%s\nseq=%s time=%s\n",
		clientMsg, formatRequestHeaders(r), r.URL.Query().Get("seq"), time.Now().UTC().Format(time.RFC3339Nano),
	))
}

func setFakeResponseHeaders(w http.ResponseWriter, r *http.Request, endpoint, stack string) {
	seq := r.URL.Query().Get("seq")
	w.Header().Set("X-NetObserv-Stack", stack)
	w.Header().Set("X-NetObserv-Endpoint", endpoint)
	w.Header().Set("X-Fake-Authorization", fmt.Sprintf("Bearer fake-%s-demo-token", stack))
	w.Header().Set("X-Fake-Trace-Id", fmt.Sprintf("%s-resp-%s-%s", stack, endpoint, seq))
	w.Header().Set("X-Fake-Tenant", fmt.Sprintf("demo-%s", stack))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
}

func formatRequestHeaders(r *http.Request) string {
	var lines []string
	for _, key := range fakeRequestHeaderKeys {
		for _, value := range r.Header.Values(key) {
			lines = append(lines, fmt.Sprintf("  %s: %s", key, value))
		}
	}
	if len(lines) == 0 {
		return "  (none)"
	}
	return strings.Join(lines, "\n")
}

func writePlaintext(w http.ResponseWriter, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write([]byte(body))
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func generateSelfSignedCert() (tls.Certificate, error) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return tls.Certificate{}, err
	}

	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: "gotls-test-pod"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{"gotls-test", "localhost"},
	}

	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	return tls.X509KeyPair(certPEM, keyPEM)
}
