package com.aethelis.islandsound.server.model;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Host -&gt; Server -&gt; All Guests, sent every 3 seconds (Section 6.4).
 * Mirrors the Swift {@code SyncMessage} struct field-for-field.
 *
 * {@code @JsonProperty} on {@code isPlaying} pins the JSON key to
 * "isPlaying" -- without it, Jackson's bean-naming convention for a
 * {@code boolean isPlaying} accessor would serialise it as "playing".
 */
public record SyncMessage(
        String type,
        String trackId,
        String trackTitle,
        String artist,
        double position,
        @JsonProperty("isPlaying") boolean isPlaying,
        long timestamp
) {
}
