package com.aethelis.islandsound.server;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Collaborative listening rooms backend (FEATURE 3 / Section 6).
 *
 * Exposes:
 * - {@code POST /api/rooms} to mint a new room code
 * - a raw STOMP-over-WebSocket endpoint at {@code /ws} (no SockJS) that the
 *   macOS client connects to directly via {@code URLSessionWebSocketTask}
 */
@SpringBootApplication
@EnableScheduling
public class IslandSoundServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(IslandSoundServerApplication.class, args);
    }
}
