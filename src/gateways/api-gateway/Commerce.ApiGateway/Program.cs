using Commerce.BuildingBlocks.Hosting;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCommercePlatformFoundation("api-gateway");
builder.Services.AddOpenApi();
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();

app.UseCommercePlatformFoundation();
app.MapOpenApi();
app.MapReverseProxy();

app.Run();

public partial class Program;
