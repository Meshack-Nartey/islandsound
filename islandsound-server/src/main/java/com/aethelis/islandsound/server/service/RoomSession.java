package com.aethelis.islandsound.server.service;

import com.aethelis.islandsound.server.model.Participant;

import java.time.Instant;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * In-memory state for one collaborative listening room.
 */
public final class RoomSession {
    private final String code;
    private final CopyOnWriteArrayList<Participant> participants = new CopyOnWriteArrayList<>();
    private volatile Instant lastActivity = Instant.now();

    public RoomSession(String code) {
        this.code = code;
    }

    public String code() {
        return code;
    }

    public List<Participant> participants() {
        return participants;
    }

    public void addParticipant(Participant participant) {
        participants.removeIf(p -> p.name().equals(participant.name()));
        participants.add(participant);
        touch();
    }

    public void removeParticipant(Participant participant) {
        participants.removeIf(p -> p.name().equals(participant.name()));
        touch();
    }

    public Instant lastActivity() {
        return lastActivity;
    }

    public void touch() {
        lastActivity = Instant.now();
    }
}
