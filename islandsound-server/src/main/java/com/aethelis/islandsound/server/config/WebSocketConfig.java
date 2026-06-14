package com.aethelis.islandsound.server.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * STOMP-over-WebSocket configuration (Section 6.2/6.4).
 *
 * The macOS client speaks raw STOMP frames over a plain WebSocket via
 * {@code URLSessionWebSocketTask} (no SockJS, no third-party client library
 * on either side), so the endpoint is registered without
 * {@code .withSockJS()}.
 *
 * - Clients SUBSCRIBE to {@code /topic/room/{code}} to receive broadcasts.
 * - Clients SEND to {@code /app/room/{code}/...} for join/sync/reaction/leave.
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic");
        registry.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*");
    }
}
