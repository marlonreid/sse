using System.Threading.Channels;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<SSEConnectionTracker>();

builder.WebHost.ConfigureKestrel(serverOptions => 
{
    serverOptions.Limits.MaxConcurrentConnections = 0;
    serverOptions.ListenAnyIP(8080, listenOptions => 
    {
        listenOptions.UseLinuxSocketTransport();
    });
});

var app = builder.Build();

app.MapGet("/sse", async (HttpContext context, SSEConnectionTracker tracker) =>
{
    context.Response.ContentType = "text/event-stream";
    tracker.AddConnection();
    
    try
    {
        var tcs = new TaskCompletionSource();
        context.RequestAborted.Register(() => tcs.SetResult());
        await tcs.Task;
    }
    finally
    {
        tracker.RemoveConnection();
    }
});

app.MapGet("/metrics", (SSEConnectionTracker tracker) => 
    Results.Ok(new { activeConnections = tracker.ActiveConnections }));

app.Run();

public class SSEConnectionTracker
{
    private int _connections = 0;
    
    public int ActiveConnections => Volatile.Read(ref _connections);
    
    public void AddConnection() => Interlocked.Increment(ref _connections);
    public void RemoveConnection() => Interlocked.Decrement(ref _connections);
}
