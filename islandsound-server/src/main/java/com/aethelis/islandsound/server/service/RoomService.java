package com.aethelis.islandsound.server.service;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * In-memory registry of active collaborative listening rooms (Section 6).
 *
 * Room codes are 6 characters drawn from a 31-character alphabet that omits
 * visually ambiguous characters (0/O, 1/I/L) so they're easy to read aloud
 * or type. A scheduled sweep evicts rooms that have seen no activity (sync,
 * reaction, join/leave) for {@link #ROOM_TTL}.
 */
@Service
public class RoomService {
    private static final String CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
    private static final int CODE_LENGTH = 6;
    private static final Duration ROOM_TTL = Duration.ofHours(6);

    private final SecureRandom random = new SecureRandom();
    private final Map<String, RoomSession> rooms = new ConcurrentHashMap<>();

    /** Creates a new room with a unique code and returns the code. */
    public String createRoom() {
        String code;
        RoomSession session;
        do {
            code = generateCode();
            session = new RoomSession(code);
        } while (rooms.putIfAbsent(code, session) != null);
        return code;
    }

    /** Returns the room for `code`, or `null` if it doesn't exist (expired or never created). */
    public RoomSession get(String code) {
        return rooms.get(code);
    }

    /** Removes the room if it has no participants left (called after a `leave`). */
    public void removeIfEmpty(String code) {
        rooms.computeIfPresent(code, (key, session) -> session.participants().isEmpty() ? null : session);
    }

    private String generateCode() {
        StringBuilder sb = new StringBuilder(CODE_LENGTH);
        for (int i = 0; i < CODE_LENGTH; i++) {
            sb.append(CODE_ALPHABET.charAt(random.nextInt(CODE_ALPHABET.length())));
        }
        return sb.toString();
    }

    /** Evicts rooms that have been inactive for longer than {@link #ROOM_TTL}, every minute. */
    @Scheduled(fixedRate = 60_000)
    public void evictStaleRooms() {
        Instant cutoff = Instant.now().minus(ROOM_TTL);
        rooms.entrySet().removeIf(entry -> entry.getValue().lastActivity().isBefore(cutoff));
    }
}
