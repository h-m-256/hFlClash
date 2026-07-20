package main

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"strings"
	"time"

	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/ca"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
)

// testProxyDelay avoids changing Mihomo health state when a user cancels a
// manual batch test.
func testProxyDelay(
	ctx context.Context,
	proxy C.Proxy,
	rawURL string,
	expectedStatus utils.IntRanges[uint16],
) (uint16, error) {
	metadata, err := delayTestMetadata(rawURL)
	if err != nil {
		return 0, err
	}

	start := time.Now()
	instance, err := proxy.DialContext(ctx, &metadata)
	if err != nil {
		return 0, err
	}
	defer instance.Close()

	req, err := http.NewRequest(http.MethodHead, rawURL, nil)
	if err != nil {
		return 0, err
	}
	req = req.WithContext(ctx)

	tlsConfig, err := ca.GetTLSConfig(ca.Option{})
	if err != nil {
		return 0, err
	}
	transport := &http.Transport{
		DialContext: func(context.Context, string, string) (net.Conn, error) {
			return instance, nil
		},
		MaxIdleConns:          100,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ExpectContinueTimeout: time.Second,
		TLSClientConfig:       tlsConfig,
	}
	client := http.Client{
		Timeout:       30 * time.Second,
		Transport:     transport,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	defer client.CloseIdleConnections()

	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	_ = resp.Body.Close()

	if adapter.UnifiedDelay.Load() {
		second := time.Now()
		secondResp, secondErr := client.Do(req)
		if secondErr == nil {
			resp = secondResp
			_ = resp.Body.Close()
			start = second
		} else if strings.HasPrefix(rawURL, "http://") {
			log.Errorln("%s failed to get the second response from %s: %v", proxy.Name(), rawURL, secondErr)
		}
	}

	if expectedStatus != nil && !expectedStatus.Check(uint16(resp.StatusCode)) {
		return 0, fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	return uint16(time.Since(start) / time.Millisecond), nil
}

func delayTestMetadata(rawURL string) (C.Metadata, error) {
	var metadata C.Metadata
	u, err := url.Parse(rawURL)
	if err != nil {
		return metadata, err
	}

	port := u.Port()
	if port == "" {
		switch u.Scheme {
		case "https":
			port = "443"
		case "http":
			port = "80"
		default:
			return metadata, fmt.Errorf("unsupported URL scheme: %s", u.Scheme)
		}
	}
	err = metadata.SetRemoteAddress(net.JoinHostPort(u.Hostname(), port))
	return metadata, err
}
