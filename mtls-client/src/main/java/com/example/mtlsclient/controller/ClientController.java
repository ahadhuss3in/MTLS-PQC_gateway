// java
package com.example.mtlsclient.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;

@RestController
public class ClientController {

    private final WebClient webClient;

    @Autowired
    public ClientController(WebClient webClient) {
        this.webClient = webClient;
    }

    @GetMapping("/call-server")
    public ResponseEntity<String> callServer() {
        // synchronous for simplicity; in reactive app use Mono/Flux
        String resp = webClient.get()
                .uri("/server")
                .retrieve()
                .bodyToMono(String.class)
                .block();
        return ResponseEntity.ok(resp);
    }
}
