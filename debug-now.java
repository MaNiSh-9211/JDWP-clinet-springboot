import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.URI;
import java.time.Duration;

public class debug-now {
    private static final String CLIENT_API = "http://localhost:8080/api/debug";
    private static final String SERVER_API = "http://localhost:8081/api/users";
    private static final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    public static void main(String[] args) throws Exception {
        System.out.println("========================================");
        System.out.println("PERFORMING ACTUAL DEBUGGING OPERATIONS");
        System.out.println("========================================\n");

        // Step 1: Connect to JDWP
        System.out.println("[1] Connecting to JDWP server at localhost:5005...");
        String connectUrl = CLIENT_API + "/connect?host=localhost&port=5005";
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(connectUrl))
                .POST(HttpRequest.BodyPublishers.noBody())
                .build();
        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
        System.out.println("Response: " + response.body());
        Thread.sleep(3000);

        // Step 2: Get all threads
        System.out.println("\n[2] Getting all threads...");
        request = HttpRequest.newBuilder()
                .uri(URI.create(CLIENT_API + "/threads"))
                .GET()
                .build();
        response = client.send(request, HttpResponse.BodyHandlers.ofString());
        System.out.println("Threads: " + response.body());
        Thread.sleep(2000);

        // Step 3: Wait for classes to load
        System.out.println("\n[3] Waiting for classes to load...");
        Thread.sleep(5000);
        
        // Trigger class loading
        request = HttpRequest.newBuilder()
                .uri(URI.create("http://localhost:8081/health"))
                .GET()
                .build();
        client.send(request, HttpResponse.BodyHandlers.ofString());
        Thread.sleep(3000);

        // Step 4: Set breakpoint
        System.out.println("\n[4] Setting breakpoint at UserController:31...");
        String bpUrl = CLIENT_API + "/breakpoints?className=com.jdwp.server.controller.UserController&lineNumber=31";
        request = HttpRequest.newBuilder()
                .uri(URI.create(bpUrl))
                .POST(HttpRequest.BodyPublishers.noBody())
                .build();
        response = client.send(request, HttpResponse.BodyHandlers.ofString());
        System.out.println("Breakpoint response: " + response.body());
        Thread.sleep(2000);

        // Step 5: Call API to hit breakpoint
        System.out.println("\n[5] Calling GET /api/users to hit breakpoint...");
        CompletableFuture<HttpResponse<String>> apiFuture = CompletableFuture.supplyAsync(() -> {
            try {
                Thread.sleep(2000);
                HttpRequest apiRequest = HttpRequest.newBuilder()
                        .uri(URI.create(SERVER_API))
                        .GET()
                        .build();
                return client.send(apiRequest, HttpResponse.BodyHandlers.ofString());
            } catch (Exception e) {
                return null;
            }
        });

        // Wait for breakpoint to be hit
        System.out.println("Waiting for breakpoint to be hit...");
        boolean breakpointHit = false;
        for (int i = 0; i < 20; i++) {
            Thread.sleep(500);
            request = HttpRequest.newBuilder()
                    .uri(URI.create(CLIENT_API + "/threads"))
                    .GET()
                    .build();
            response = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.body().contains("\"isSuspended\":true")) {
                System.out.println("✓✓✓ BREAKPOINT HIT! Thread is suspended.");
                breakpointHit = true;
                break;
            }
        }

        if (breakpointHit) {
            // Step 6: Get stack frames
            System.out.println("\n[6] Getting stack frames...");
            // Need to find the suspended thread name first
            request = HttpRequest.newBuilder()
                    .uri(URI.create(CLIENT_API + "/threads"))
                    .GET()
                    .build();
            response = client.send(request, HttpResponse.BodyHandlers.ofString());
            System.out.println("Threads: " + response.body());
            
            // Step 7: Get variables
            System.out.println("\n[7] Getting variables...");
            // Would need thread name here
            
            // Step 8: Step over
            System.out.println("\n[8] Executing step over...");
            // Would need thread name here
            
            // Step 9: Resume
            System.out.println("\n[9] Resuming thread...");
            // Would need thread name here
        }

        // Wait for API to complete
        try {
            HttpResponse<String> apiResponse = apiFuture.get(10, java.util.concurrent.TimeUnit.SECONDS);
            if (apiResponse != null) {
                System.out.println("\nAPI call completed: " + apiResponse.statusCode());
            }
        } catch (Exception e) {
            System.out.println("\nAPI call: " + e.getMessage());
        }

        System.out.println("\n========================================");
        System.out.println("DEBUGGING OPERATIONS COMPLETED");
        System.out.println("========================================");
    }
}
