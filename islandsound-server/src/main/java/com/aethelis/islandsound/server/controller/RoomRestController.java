package com.aethelis.islandsound.server.controller;

import com.aethelis.islandsound.server.model.RoomCreatedResponse;
import com.aethelis.islandsound.server.service.RoomService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * REST entry point for creating a collaborative listening room
 * (Section 6.1). The returned code is then used to connect over the STOMP
 * WebSocket at {@code /ws} and subscribe to {@code /topic/room/{code}}.
 */
@RestController
@RequestMapping("/api/rooms")
public class RoomRestController {

    private final RoomService roomService;

    public RoomRestController(RoomService roomService) {
        this.roomService = roomService;
    }

    @PostMapping
    public RoomCreatedResponse createRoom() {
        return new RoomCreatedResponse(roomService.createRoom());
    }
}
