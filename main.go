package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const releaseURL = "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz"

const (
	panelPort = "20530"

	// VLESS + WebSocket
	vlessPort   = "20868"
	vlessPrefix = "/xvpnws/"

	// VLESS + XHTTP
	xhttpPort   = "20869"
	xhttpPrefix = "/xhttp/"

	// Subscription
	subPort   = "2096"
	subPrefix = "/sub/"
)

func main() {
	// Deplexo provides PORT automatically.
	// If it doesn't exist, use 2053.
	publicPort := os.Getenv("PORT")
	if publicPort == "" {
		publicPort = "2053"
	}

	installDir := "/app/x-ui"
	binPath := filepath.Join(installDir, "x-ui")

	// Normally Dockerfile already downloads 3x-ui.
	// This is only a fallback.
	if _, err := os.Stat(binPath); os.IsNotExist(err) {
		fmt.Println("Downloading official 3x-ui release...")

		if err := downloadAndExtract(releaseURL, "/app"); err != nil {
			fmt.Println("download error:", err)
			os.Exit(1)
		}
	}

	if err := os.Chmod(binPath, 0755); err != nil {
		fmt.Println("chmod error:", err)
	}

	filepath.Walk(
		filepath.Join(installDir, "bin"),
		func(path string, info os.FileInfo, err error) error {
			if err == nil && info != nil && !info.IsDir() {
				_ = os.Chmod(path, 0755)
			}
			return nil
		},
	)

	dataDir := "/app/data"

	_ = os.MkdirAll(dataDir, 0755)
	_ = os.MkdirAll(filepath.Join(dataDir, "logs"), 0755)

	cmd := exec.Command(binPath)

	cmd.Dir = installDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	cmd.Env = append(
		os.Environ(),

		"XUI_DB_FOLDER="+dataDir,
		"XUI_LOG_FOLDER="+filepath.Join(dataDir, "logs"),
		"XUI_PORT="+panelPort,
	)

	if err := cmd.Start(); err != nil {
		fmt.Println("failed to start x-ui:", err)
		os.Exit(1)
	}

	go startProxy(publicPort)

	if err := cmd.Wait(); err != nil {
		fmt.Println("run error:", err)
		os.Exit(1)
	}
}

func startProxy(publicPort string) {

	// Give 3x-ui / Xray a moment to initialize.
	time.Sleep(3 * time.Second)

	panelTarget, _ := url.Parse(
		"http://127.0.0.1:" + panelPort,
	)

	vlessTarget, _ := url.Parse(
		"http://127.0.0.1:" + vlessPort,
	)

	xhttpTarget, _ := url.Parse(
		"http://127.0.0.1:" + xhttpPort,
	)

	subTarget, _ := url.Parse(
		"http://127.0.0.1:" + subPort,
	)

	panelProxy :=
		httputil.NewSingleHostReverseProxy(panelTarget)

	vlessProxy :=
		httputil.NewSingleHostReverseProxy(vlessTarget)

	xhttpProxy :=
		httputil.NewSingleHostReverseProxy(xhttpTarget)

	subProxy :=
		httputil.NewSingleHostReverseProxy(subTarget)

	/*
		Immediate flushing is useful for
		long-lived / streaming XHTTP connections.
	*/
	xhttpProxy.FlushInterval = -1

	vlessProxy.FlushInterval = -1

	mux := http.NewServeMux()

	mux.HandleFunc(
		"/",
		func(w http.ResponseWriter, r *http.Request) {

			switch {

			// VLESS + WebSocket
			case strings.HasPrefix(
				r.URL.Path,
				vlessPrefix,
			):

				vlessProxy.ServeHTTP(w, r)

			// VLESS + XHTTP
			case strings.HasPrefix(
				r.URL.Path,
				xhttpPrefix,
			):

				xhttpProxy.ServeHTTP(w, r)

			// 3x-ui subscription
			case strings.HasPrefix(
				r.URL.Path,
				subPrefix,
			):

				subProxy.ServeHTTP(w, r)

			// Everything else goes to 3x-ui panel
			default:

				panelProxy.ServeHTTP(w, r)
			}
		},
	)

	fmt.Println(
		"Reverse proxy listening on :" + publicPort,
	)

	fmt.Println(
		"Panel route: / -> 127.0.0.1:" + panelPort,
	)

	fmt.Println(
		"WebSocket route: " +
			vlessPrefix +
			" -> 127.0.0.1:" +
			vlessPort,
	)

	fmt.Println(
		"XHTTP route: " +
			xhttpPrefix +
			" -> 127.0.0.1:" +
			xhttpPort,
	)

	fmt.Println(
		"Subscription route: " +
			subPrefix +
			" -> 127.0.0.1:" +
			subPort,
	)

	if err := http.ListenAndServe(
		":"+publicPort,
		mux,
	); err != nil {

		fmt.Println(
			"proxy error:",
			err,
		)

		os.Exit(1)
	}
}

func downloadAndExtract(
	srcURL string,
	dest string,
) error {

	resp, err := http.Get(srcURL)

	if err != nil {
		return err
	}

	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {

		return fmt.Errorf(
			"bad status: %s",
			resp.Status,
		)
	}

	gz, err := gzip.NewReader(resp.Body)

	if err != nil {
		return err
	}

	defer gz.Close()

	tr := tar.NewReader(gz)

	for {

		hdr, err := tr.Next()

		if err == io.EOF {
			break
		}

		if err != nil {
			return err
		}

		target := filepath.Join(
			dest,
			hdr.Name,
		)

		switch hdr.Typeflag {

		case tar.TypeDir:

			if err := os.MkdirAll(
				target,
				0755,
			); err != nil {

				return err
			}

		case tar.TypeReg:

			if err := os.MkdirAll(
				filepath.Dir(target),
				0755,
			); err != nil {

				return err
			}

			f, err := os.OpenFile(
				target,
				os.O_CREATE|
					os.O_WRONLY|
					os.O_TRUNC,
				os.FileMode(hdr.Mode),
			)

			if err != nil {
				return err
			}

			if _, err := io.Copy(
				f,
				tr,
			); err != nil {

				f.Close()

				return err
			}

			f.Close()
		}
	}

	return nil
}
