using System.Threading.Channels;

var builder = WebApplication.CreateBuilder(args);

// Add Redis for connection tracking
builder.Services.AddStackExchangeRedisCache(options => {
    options.Configuration = "redis:6379";
});

builder.WebHost.ConfigureKestrel(serverOptions => 
{
    serverOptions.Limits.MaxConcurrentConnections = 0;
    serverOptions.ListenAnyIP(8080, listenOptions => 
    {
        listenOptions.UseLinuxSocketTransport();
    });
});

var app = builder.Build();

app.MapGet("/sse", async (HttpContext context) =>
{
    context.Response.ContentType = "text/event-stream";
    var redis = context.RequestServices.GetRequiredService<IDistributedCache>();
    
    // Track connection
    await redis.IncrementAsync("active_connections");
    
    try
    {
        var tcs = new TaskCompletionSource();
        context.RequestAborted.Register(() => tcs.SetResult());
        await tcs.Task;
    }
    finally
    {
        await redis.DecrementAsync("active_connections");
    }
});

app.MapGet("/metrics", async (IDistributedCache redis) => 
{
    var connections = await redis.GetStringAsync("active_connections");
    return Results.Ok(new { connections });
});

app.Run();

public static class RedisExtensions
{
    public static async Task IncrementAsync(this IDistributedCache cache, string key)
    {
        var value = await cache.GetStringAsync(key) ?? "0";
        var newValue = (long.Parse(value) + 1).ToString();
        await cache.SetStringAsync(key, newValue);
    }

    public static async Task DecrementAsync(this IDistributedCache cache, string key)
    {
        var value = await cache.GetStringAsync(key) ?? "0";
        var newValue = (long.Parse(value) - 1).ToString();
        await cache.SetStringAsync(key, newValue);
    }
}
