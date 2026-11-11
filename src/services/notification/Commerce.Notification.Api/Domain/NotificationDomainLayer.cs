namespace Commerce.Notification.Domain;

/// <summary>
/// Pure Domain layer for Notification Service (Notification delivery state, template policies).
/// Must NOT depend on ASP.NET Core, EF Core, Npgsql, SMTP/Mailpit clients, Kafka, or outer layers.
/// </summary>
public static class NotificationDomainLayer;
