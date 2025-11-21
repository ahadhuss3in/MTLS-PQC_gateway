package com.example.mtlsfz.Controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController("")
public class HelloController {

    @GetMapping("/server")
    public String hello() {
        return "Secured Data";
    }
}