package main

import (
	"context"
	"sync"
)

type delayTestSession struct {
	context context.Context
	cancel  context.CancelFunc
}

var delayTestSessionStore = struct {
	sync.Mutex
	sessions map[string]*delayTestSession
}{
	sessions: map[string]*delayTestSession{},
}

func handleStartDelayTest(id string) bool {
	if id == "" {
		return false
	}

	delayTestSessionStore.Lock()
	defer delayTestSessionStore.Unlock()
	if _, exists := delayTestSessionStore.sessions[id]; exists {
		return false
	}

	ctx, cancel := context.WithCancel(context.Background())
	delayTestSessionStore.sessions[id] = &delayTestSession{
		context: ctx,
		cancel:  cancel,
	}
	return true
}

func handleCancelDelayTest(id string) bool {
	return removeDelayTestSession(id)
}

func handleFinishDelayTest(id string) bool {
	return removeDelayTestSession(id)
}

func removeDelayTestSession(id string) bool {
	delayTestSessionStore.Lock()
	session, exists := delayTestSessionStore.sessions[id]
	if exists {
		delete(delayTestSessionStore.sessions, id)
	}
	delayTestSessionStore.Unlock()
	if !exists {
		return false
	}

	session.cancel()
	return true
}

func getDelayTestContext(id string) (context.Context, bool) {
	if id == "" {
		return context.Background(), true
	}

	delayTestSessionStore.Lock()
	session, exists := delayTestSessionStore.sessions[id]
	delayTestSessionStore.Unlock()
	if !exists {
		return nil, false
	}
	return session.context, true
}

func handleCancelAllDelayTests() {
	delayTestSessionStore.Lock()
	sessions := delayTestSessionStore.sessions
	delayTestSessionStore.sessions = map[string]*delayTestSession{}
	delayTestSessionStore.Unlock()

	for _, session := range sessions {
		session.cancel()
	}
}
