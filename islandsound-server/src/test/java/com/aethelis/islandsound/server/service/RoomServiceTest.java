package com.aethelis.islandsound.server.service;

import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RoomServiceTest {

    @Test
    void createRoomReturnsSixCharacterUnambiguousCode() {
        RoomService service = new RoomService();
        String code = service.createRoom();

        assertEquals(6, code.length());
        assertTrue(code.chars().allMatch(c -> "23456789ABCDEFGHJKMNPQRSTUVWXYZ".indexOf(c) >= 0));
        assertNotNull(service.get(code));
    }

    @Test
    void createRoomGeneratesUniqueCodes() {
        RoomService service = new RoomService();
        Set<String> codes = new HashSet<>();
        for (int i = 0; i < 100; i++) {
            codes.add(service.createRoom());
        }
        assertEquals(100, codes.size());
    }

    @Test
    void removeIfEmptyDropsRoomWithNoParticipants() {
        RoomService service = new RoomService();
        String code = service.createRoom();

        service.removeIfEmpty(code);

        assertNull(service.get(code));
    }
}
