package main

import (
	"encoding/json"
	"testing"
	"time"
)

func TestDelayTestSessionCancellation(t *testing.T) {
	const id = "delay-test-cancel"
	defer handleFinishDelayTest(id)

	if !handleStartDelayTest(id) {
		t.Fatal("failed to start delay test session")
	}
	if handleStartDelayTest(id) {
		t.Fatal("duplicate delay test session was accepted")
	}

	ctx, exists := getDelayTestContext(id)
	if !exists {
		t.Fatal("delay test session context not found")
	}
	if !handleCancelDelayTest(id) {
		t.Fatal("failed to cancel delay test session")
	}
	if _, exists := getDelayTestContext(id); exists {
		t.Fatal("cancelled delay test session was not removed")
	}

	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("delay test context was not cancelled")
	}
}

func TestFinishDelayTestRemovesSession(t *testing.T) {
	const id = "delay-test-finish"
	if !handleStartDelayTest(id) {
		t.Fatal("failed to start delay test session")
	}
	ctx, exists := getDelayTestContext(id)
	if !exists {
		t.Fatal("delay test session context not found")
	}

	if !handleFinishDelayTest(id) {
		t.Fatal("failed to finish delay test session")
	}
	if _, exists := getDelayTestContext(id); exists {
		t.Fatal("finished delay test session was not removed")
	}

	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("finished delay test context was not cancelled")
	}
}

func TestCancelledDelayTestSkipsQueuedProxyTest(t *testing.T) {
	const id = "delay-test-queued"
	defer handleFinishDelayTest(id)
	if !handleStartDelayTest(id) {
		t.Fatal("failed to start delay test session")
	}
	if !handleCancelDelayTest(id) {
		t.Fatal("failed to cancel delay test session")
	}

	params, err := json.Marshal(TestDelayParams{
		ProxyName: "missing-proxy",
		TestUrl:   "https://example.com",
		TestId:    id,
		Timeout:   5000,
	})
	if err != nil {
		t.Fatal(err)
	}
	result := make(chan string, 1)
	handleAsyncTestDelay(string(params), func(value string) {
		result <- value
	})

	select {
	case value := <-result:
		var delay Delay
		if err := json.Unmarshal([]byte(value), &delay); err != nil {
			t.Fatal(err)
		}
		if delay.Value != -1 {
			t.Fatalf("unexpected delay result: %d", delay.Value)
		}
	case <-time.After(time.Second):
		t.Fatal("cancelled delay test did not finish immediately")
	}
}
