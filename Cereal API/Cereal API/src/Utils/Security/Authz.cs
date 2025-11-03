// CerealAPI/src/Utils/Security/Authz.cs
using CerealAPI.Data;
using Dapper;

/*
*   Taget brug af gammel kode fra tidligere projekter:
*   - https://github.com/saphyron/C--Backend/tree/main
*/
namespace CerealAPI.Utils.Security;
/// <summary>
/// Hjælpeklasse til authZ/authN: finder hemmelig nøgle, udtrækker token fra request,
/// og oversætter et gyldigt JWT til en aktuel bruger slået op i databasen.
/// </summary>
/// <remarks>
/// Metoderne er statiske og sideeffektfrie. Token læses i prioritet: cookie → Authorization-header.
/// Ved brugerresolution valideres JWT (signatur/issuer/audience/udløb) og derefter slås brugeren op,
/// så slettede/deaktiverede roller ikke får adgang på gamle tokens.
/// </remarks>
public static class Authz
{
    /// <summary>
    /// Henter JWT-hemmeligheden fra konfigurationen.
    /// </summary>
    /// <param name="cfg">App-konfiguration (IConfiguration).</param>
    /// <returns>Den anvendte signing key (secret). Fallback er en udviklingsnøgle.</returns>
    /// <remarks>
    /// Understøtter både nøglenavne <c>Jwt:SigningKey</c> og <c>JWT_SECRET</c> for fleksibilitet.
    /// Returværdien bør sættes via miljøvariabler i produktion.
    /// </remarks>
    public static string GetJwtSecret(IConfiguration cfg)
        => cfg["Jwt:SigningKey"]
        ?? cfg["JWT_SECRET"]
        ?? "dev-only-secret-change-me";
    /// <summary>
    /// Forsøger at læse et JWT fra den aktuelle HTTP-request.
    /// </summary>
    /// <param name="ctx">HTTP-konteksten for den indgående anmodning.</param>
    /// <returns>Strengen med token hvis fundet, ellers <c>null</c>.</returns>
    /// <remarks>
    /// Læseorden: 1) HttpOnly cookie med navnet <c>token</c>, 2) <c>Authorization: Bearer ...</c>.
    /// </remarks>
    public static string? TryGetToken(HttpContext ctx)
    {
        // 1) Cookie (HttpOnly)
        if (ctx.Request.Cookies.TryGetValue("token", out var cookieToken) &&
            !string.IsNullOrEmpty(cookieToken))
            return cookieToken;

        // 2) Fallback: Authorization: Bearer ...
        var auth = ctx.Request.Headers.Authorization.ToString();
        if (!string.IsNullOrWhiteSpace(auth) &&
            auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return auth.Substring("Bearer ".Length).Trim();

        return null;
    }

    /// <summary>
    /// Validerer token og returnerer den aktuelle bruger hvis både token og DB slå-op er gyldigt.
    /// </summary>
    /// <param name="factory">SQL-connection factory til DB-opslag.</param>
    /// <param name="ctx">HTTP-kontekst (bruges til at finde token).</param>
    /// <param name="cfg">Konfiguration (issuer, audience, secret).</param>
    /// <returns>
    /// En <c>JwtHelper.JwtUser</c> med <c>UserId</c>, <c>Username</c> og <c>Role</c> hvis alt er OK; ellers <c>null</c>.
    /// </returns>
    /// <remarks>
    /// Trin: (1) Hent token fra request, (2) valider signatur/claims via <c>JwtHelper.Validate</c>,
    /// (3) slå brugeren op i <c>dbo.Users</c>. Returnerer <c>null</c> hvis noget fejler.
    /// </remarks>
    public static async Task<JwtHelper.JwtUser?> GetCurrentUserAsync(
        SqlConnectionCeral factory,
        HttpContext ctx,
        IConfiguration cfg)
    {
        var token = TryGetToken(ctx);
        if (string.IsNullOrEmpty(token)) return null;

        var issuer = cfg["Jwt:Issuer"] ?? cfg["JWT_ISSUER"];
        var audience = cfg["Jwt:Audience"] ?? cfg["JWT_AUDIENCE"];
        var secret = GetJwtSecret(cfg);

        var u = JwtHelper.Validate(token, secret, issuer, audience);
        if (u is null) return null;

        using var conn = factory.Create();
        // Slår minimal info op for at sikre at brugeren stadig findes og for at hente aktuel rolle
        var row = await conn.QuerySingleOrDefaultAsync<(int Id, string Username, string Role)>(
            "SELECT Id, Username, Role FROM dbo.Users WHERE Username=@u",
            new { u = u.Username });

        if (row.Id == 0) return null;

        // Returner normaliserede claims til resten af pipelinen
        return new JwtHelper.JwtUser
        {
            UserId = row.Id,
            Username = row.Username,
            Role = row.Role
        };
    }
}
