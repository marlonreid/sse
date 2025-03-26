To test Server-Sent Events (SSE) using NBomber, you'll need to create a custom scenario that simulates SSE clients. Here's a step-by-step guide and example code:

Step 1: Install NBomber Packages
bash
Copy
dotnet add package NBomber
dotnet add package NBomber.Http
Step 2: Create SSE Client Helper
csharp
Copy
using System;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

public class SseClient : IDisposable
{
    private readonly HttpClient _client;
    private readonly CancellationTokenSource _cts;

    public SseClient(HttpClient client)
    {
        _client = client;
        _cts = new CancellationTokenSource();
    }

    public async Task ConnectAsync(string url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Accept.Add(new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("text/event-stream"));

        var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        var stream = await response.Content.ReadAsStreamAsync();
        var reader = new System.IO.StreamReader(stream);

        // Start reading events in background
        _ = Task.Run(async () =>
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync();
                if (line == null) break;
                // Process event here if needed
            }
        });
    }

    public void Dispose() => _cts.Cancel();
}
Step 3: Create NBomber Scenario
csharp
Copy
using System;
using System.Net.Http;
using System.Threading.Tasks;
using NBomber.CSharp;
using NBomber.Plugins.Http.CSharp;

public class SseScenario
{
    public static void Run()
    {
        var httpFactory = HttpClientFactory.Create();

        var sseStep = Step.Create("sse_connection", httpFactory, async context =>
        {
            try
            {
                var sseClient = new SseClient(context.Client);
                await sseClient.ConnectAsync("https://your-sse-endpoint");
                
                // Keep connection open for 30 seconds
                await Task.Delay(TimeSpan.FromSeconds(30));
                
                sseClient.Dispose();
                return Response.Ok();
            }
            catch (Exception ex)
            {
                return Response.Fail(ex);
            }
        });

        var scenario = ScenarioBuilder
            .CreateScenario("sse_test", sseStep)
            .WithWarmUpDuration(TimeSpan.FromSeconds(5))
            .WithLoadSimulations(
                Simulation.KeepConstant(copies: 100, during: TimeSpan.FromSeconds(30))
            );

        NBomberRunner
            .RegisterScenarios(scenario)
            .Run();
    }
}
Key Components:
SSE Client Helper:

Handles SSE connection using HttpClient

Reads events in background

Properly disposes resources

NBomber Step:

Creates SSE connection per virtual user

Maintains connection for specified duration

Reports success/failure metrics

Load Simulation:

Maintains 100 concurrent connections

Runs for 30 seconds after warmup

Customization Points:
Event Processing:

Add logic in SseClient to process received events

Track metrics using context.ReportMetric()

Connection Parameters:

Adjust keep-alive duration (Task.Delay)

Modify URL and headers for your SSE endpoint

Load Configuration:

Modify KeepConstant parameters

Add ramp-up simulations if needed

To Run:
csharp
Copy
SseScenario.Run();
Analysis:
After running the test, NBomber will provide statistics about:

Successful/Failed connections

Latency metrics

Data transfer statistics

Connection lifetime durations

This approach helps validate:

Server's ability to handle concurrent SSE connections

Stability of long-lived connections

Proper event streaming under load

Remember to adjust timeouts and load parameters according to your specific requirements.

