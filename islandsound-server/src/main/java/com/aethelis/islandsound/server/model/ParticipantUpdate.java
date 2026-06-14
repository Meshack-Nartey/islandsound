package com.aethelis.islandsound.server.model;

import java.util.List;

/**
 * Server -&gt; All, sent on participant join/leave. Mirrors the Swift
 * {@code ParticipantUpdate} struct.
 */
public record ParticipantUpdate(String type, List<Participant> participants) {
    public ParticipantUpdate(List<Participant> participants) {
        this("PARTICIPANT_UPDATE", participants);
    }
}
