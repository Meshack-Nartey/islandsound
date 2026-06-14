package com.aethelis.islandsound.server.controller;

import com.aethelis.islandsound.server.model.Participant;
import com.aethelis.islandsound.server.model.ParticipantUpdate;
import com.aethelis.islandsound.server.model.ReactionMessage;
import com.aethelis.islandsound.server.model.SyncMessage;
import com.aethelis.islandsound.server.service.RoomService;
import com.aethelis.islandsound.server.service.RoomSession;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

/**
 * STOMP message handlers for an active room (Section 6.2-6.4).
 *
 * All destinations are scoped to a room by `{code}` and broadcast back to
 * every subscriber of `/topic/room/{code}` -- including the sender, which
 * is why the host filters out its own SYNC echoes on the client side
 * (`CollabEngine` only applies `onRemoteSync` for `.guest`).
 */
@Controller
public class RoomStompController {

    private final RoomService roomService;
    private final SimpMessagingTemplate messagingTemplate;

    public RoomStompController(RoomService roomService, SimpMessagingTemplate messagingTemplate) {
        this.roomService = roomService;
        this.messagingTemplate = messagingTemplate;
    }

    /** A participant joined the room -- broadcast the updated roster. */
    @MessageMapping("/room/{code}/join")
    public void join(@DestinationVariable String code, Participant participant) {
        RoomSession room = roomService.get(code);
        if (room == null) {
            return;
        }
        room.addParticipant(participant);
        broadcastRoster(code, room);
    }

    /** A participant left the room -- broadcast the updated roster and clean up if empty. */
    @MessageMapping("/room/{code}/leave")
    public void leave(@DestinationVariable String code, Participant participant) {
        RoomSession room = roomService.get(code);
        if (room == null) {
            return;
        }
        room.removeParticipant(participant);
        broadcastRoster(code, room);
        roomService.removeIfEmpty(code);
    }

    /** Host -> everyone: current playback position/track (sent every 3s). */
    @MessageMapping("/room/{code}/sync")
    public void sync(@DestinationVariable String code, SyncMessage sync) {
        RoomSession room = roomService.get(code);
        if (room == null) {
            return;
        }
        room.touch();
        messagingTemplate.convertAndSend("/topic/room/" + code, sync);
    }

    /** Guest -> everyone: an emoji reaction. */
    @MessageMapping("/room/{code}/reaction")
    public void reaction(@DestinationVariable String code, ReactionMessage reaction) {
        RoomSession room = roomService.get(code);
        if (room == null) {
            return;
        }
        room.touch();
        messagingTemplate.convertAndSend("/topic/room/" + code, reaction);
    }

    private void broadcastRoster(String code, RoomSession room) {
        messagingTemplate.convertAndSend("/topic/room/" + code, new ParticipantUpdate(room.participants()));
    }
}
