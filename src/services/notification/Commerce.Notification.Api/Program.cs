using Commerce.BuildingBlocks.Hosting;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCommercePlatformFoundation("notification-service");
builder.Services.AddOpenApi();

var app = builder.Build();

app.UseCommercePlatformFoundation();
app.MapOpenApi();

app.Run();

public partial class Program;
