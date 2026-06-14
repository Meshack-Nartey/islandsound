package com.aethelis.islandsound.server.model;

/**
 * Guest -&gt; Server -&gt; Host (and everyone else in the room), sent on a
 * reaction tap (Section 6.3). Mirrors the Swift {@code ReactionMessage} struct.
 */
public record ReactionMessage(String type, String emoji, String from) {
}
