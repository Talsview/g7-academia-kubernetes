package br.senai.g7.config;

import br.senai.g7.security.JwtAuthFilter;
import br.senai.g7.security.JwtService;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Segurança da API: sessão stateless com JWT, regras por perfil e CORS restrito
 * à origem configurada e aos endereços locais usados pelo Minikube.
 */
@Configuration
public class SecurityConfig {

    @Bean
    PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http, JwtService jwt) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .cors(Customizer.withDefaults())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(a -> a
                .requestMatchers("/api/auth/login", "/actuator/health", "/actuator/prometheus").permitAll()
                .requestMatchers("/api/auditoria/**").hasRole("ADMIN")
                .requestMatchers(HttpMethod.POST, "/api/planos/**").hasRole("ADMIN")
                .requestMatchers(HttpMethod.PUT, "/api/planos/**").hasRole("ADMIN")
                .requestMatchers(HttpMethod.POST, "/api/financeiro/**").hasRole("ADMIN")
                .anyRequest().authenticated())
            .exceptionHandling(e -> e
                .authenticationEntryPoint((req, res, ex) -> escrever(res, 401, "Não autenticado"))
                .accessDeniedHandler((req, res, ex) -> escrever(res, 403, "Acesso negado para o seu perfil")))
            .addFilterBefore(new JwtAuthFilter(jwt), UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    private static void escrever(jakarta.servlet.http.HttpServletResponse res, int status, String msg)
            throws java.io.IOException {
        res.setStatus(status);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE + ";charset=UTF-8");
        res.getWriter().write("{\"status\":" + status + ",\"erro\":\"" + msg + "\",\"detalhes\":[]}");
    }

    /**
     * O frontend usa o Nginx como proxy reverso. No Minikube, a URL publicada
     * costuma ser http://127.0.0.1:<porta> (ou localhost:<porta>), enquanto
     * CORS_ALLOWED_ORIGIN mantém o valor usado no desenvolvimento local.
     * Somente loopback e o IP local padrão do Minikube são aceitos; não há '*'.
     */
    @Bean
    CorsConfigurationSource corsConfigurationSource(@Value("${g7.cors.allowed-origin}") String origem) {
        CorsConfiguration c = new CorsConfiguration();
        c.setAllowedOriginPatterns(List.of(
            origem,
            "http://127.0.0.1:*",
            "http://localhost:*",
            "http://192.168.49.2:*"
        ));
        c.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        c.setAllowedHeaders(List.of("Authorization", "Content-Type", "X-Requested-With"));
        c.setAllowCredentials(false);
        c.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource s = new UrlBasedCorsConfigurationSource();
        s.registerCorsConfiguration("/api/**", c);
        return s;
    }
}
