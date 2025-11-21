package com.example.mtlsclient.Config;

import io.netty.handler.ssl.SslContext;
import io.netty.handler.ssl.SslContextBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import reactor.netty.http.client.HttpClient;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.TrustManagerFactory;
import java.io.InputStream;
import java.security.KeyStore;

@Configuration
public class TlSConfig {

    private static final char[] PASSWORD = "password".toCharArray();

    private KeyStore loadKeyStore(String resource) throws Exception {
        // Try PKCS12 first, then JKS
        for (String type : new String[]{"PKCS12", "JKS"}) {
            try (InputStream is = new ClassPathResource(resource).getInputStream()) {
                KeyStore ks = KeyStore.getInstance(type);
                ks.load(is, PASSWORD);
                System.out.println("✓ Loaded " + resource + " as " + type);
                return ks;
            } catch (Exception e) {
            }
        }
        throw new IllegalArgumentException("Cannot load " + resource + " as PKCS12 or JKS");
    }

    @Bean
    public WebClient webClient() throws Exception {
        KeyStore keyStore = loadKeyStore("client-keystore.p12");
        KeyStore trustStore = loadKeyStore("client-truststore.jks");

        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(keyStore, PASSWORD);

        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(trustStore);

        SslContext sslContext = SslContextBuilder.forClient()
                .keyManager(kmf)
                .trustManager(tmf)
                .build();

        HttpClient httpClient = HttpClient.create()
                .secure(spec -> spec.sslContext(sslContext));

        return WebClient.builder()
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .baseUrl("https://localhost:8080")
                .build();
    }
}
