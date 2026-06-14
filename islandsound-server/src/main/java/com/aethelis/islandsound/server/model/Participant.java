package com.aethelis.islandsound.server.model;

/**
 * A participant shown in the island's avatar row. Mirrors the Swift
 * {@code Participant} struct (id == name).
 */
public record Participant(String name, String avatar) {
}
