// src/Endpoints/Authentication/AuthenticationEndpoints.cs
using CerealAPI.Data.Repository;
using CerealAPI.Utils.Security;
using Microsoft.AspNetCore.Authorization;

namespace CerealAPI.Endpoints.Authentication;
/// <summary>
/// Registrerer alle auth-relaterede endpoints under <c>/authentication</c>.
/// Indeholder sundhedstjek, registrering, login, logout og et beskyttet <c>/me</c>.
/// </summary>
/// <remarks>
/// Samler API routing ét sted for at gøre Program.cs mere overskuelig.
/// Består primært af små handlers med simpel validering og kald til repositories/hjælpeklasser.
/// </remarks>
public static class AuthenticationEndpoints
{
    /// <summary>
    /// Mapper alle autentificeringsendpoints på den givne <see cref="WebApplication"/>.
    /// </summary>
    /// <param name="app">Den aktuelle webapplikation, som endpoints registreres på.</param>
    /// <remarks>
    /// Opretter en route-gruppe <c>/auth</c>, tilføjer anonyme endpoints for health, register, login, logout
    /// og et beskyttet endpoint for <c>/auth/me</c>. I udvikling tilføjes også et lille echo-endpoint.
    /// Der bruges WebApplication, så vi kan tjekke app.Environment.IsDevelopment()
    /// </remarks>
    public static void MapAuthenticationEndpoints(this WebApplication app)
    {
        var g = app.MapGroup("/auth");

        // ÅBNE endpoints
        g.MapGet("/health", () => Results.Ok(new { ok = true })).AllowAnonymous();

        g.MapPost("/register", async (UsersRepository repo, RegisterRequest req) =>
        {
            // Basisvalidering af input
            if (req is null ||
                string.IsNullOrWhiteSpace(req.Username) ||
                string.IsNullOrWhiteSpace(req.Password))
            {
                return Results.BadRequest(new { message = "Username and password are required." });
            }
            // Tjek om brugernavn allerede findes
            var exists = await repo.GetByUsernameAsync(req.Username);
            if (exists is not null)
                return Results.Conflict(new { message = "Username already exists." });
            // Hash password og opret bruger
            var hash = PasswordHasher.Hash(req.Password);
            var newId = await repo.CreateAsync(req.Username, hash, role: "user");
            return Results.Created($"/users/{newId}", new { id = newId, username = req.Username });
        }).AllowAnonymous();

        g.MapPost("/login", async (UsersRepository repo, IConfiguration cfg, HttpContext ctx, LoginRequest req) =>
        {
            // Basisvalidering (samme fejl-signal for at undgå username enumeration)
            if (req is null ||
                string.IsNullOrWhiteSpace(req.Username) ||
                string.IsNullOrWhiteSpace(req.Password))
            {
                return Results.Unauthorized();
            }
            // Slå bruger op i DB
            // (brug GetByUsernameAsync som returnerer null hvis ikke fundet)
            var user = await repo.GetByUsernameAsync(req.Username);
            if (user is null) return Results.Unauthorized();
            // Tjek hashed password 
            var ok = PasswordHasher.LooksHashed(user.PasswordHash)
                ? PasswordHasher.Verify(req.Password, user.PasswordHash)
                : string.Equals(req.Password, user.PasswordHash, StringComparison.Ordinal);

            if (!ok) return Results.Unauthorized();
            // Migrér legacy-konto til hashed password ved succesfuldt login
            if (!PasswordHasher.LooksHashed(user.PasswordHash))
            {
                var newHash = PasswordHasher.Hash(req.Password);
                await repo.UpdatePasswordHashAsync(user.Id, newHash);
            }
            // Opret JWT og sæt cookie
            var secret = Authz.GetJwtSecret(cfg);
            var kid = cfg["JWT_KEY_VERSION"] ?? "v1";
            var iss = cfg["Jwt:Issuer"] ?? cfg["JWT_ISSUER"];
            var aud = cfg["Jwt:Audience"] ?? cfg["JWT_AUDIENCE"];
            // Lifetime 8 timer (kan justeres efter behov)
            // (brug TimeSpan.FromDays(7) for 7 dage, eller TimeSpan.FromHours(1) for 1 time osv.)
            var jwt = JwtHelper.CreateAccessToken(
                new JwtHelper.JwtUser { UserId = user.Id, Username = user.Username, Role = user.Role },
                secret, kid, lifetime: TimeSpan.FromHours(8), issuer: iss, audience: aud
            );

            // Sæt auth-cookie (HTTP-only). Over HTTP i dev sendes Secure=false automatisk via IsHttps.
            var secure = ctx.Request.IsHttps && !app.Environment.IsDevelopment();
            //var secure = ctx.Request.IsHttps; // dev over HTTP => false
            var now = DateTimeOffset.UtcNow;

            ctx.Response.Cookies.Append("token", jwt, new CookieOptions
            {
                HttpOnly = true,
                Secure = ctx.Request.IsHttps,
                SameSite = SameSiteMode.Lax, // gør redirect-flows nemmere men beskytter basale CSRF-scenarier
                Path = "/",
                MaxAge = TimeSpan.FromHours(8),
                Expires = now.AddHours(8),
                IsEssential = true
            });
            // Returnér også token i body for Bearer-usage
            return Results.Ok(new AuthResponse { Token = jwt, Username = user.Username, Role = user.Role });
        }).AllowAnonymous();

        g.MapPost("/logout", (HttpContext ctx) =>
        {
            // Overstempl cookie med udløbet dato
            ctx.Response.Cookies.Append("token", "", new CookieOptions
            {
                HttpOnly = true,
                Secure = ctx.Request.IsHttps,
                SameSite = SameSiteMode.Lax,
                Path = "/",
                Expires = DateTime.UnixEpoch
            });
            return Results.Ok(new { success = true });
        }).AllowAnonymous();

        // BESKYTTET endpoint via middleware – kraver blot login
        g.MapGet("/me", async (HttpContext ctx, UsersRepository repo) =>
        {
            // Tjek principal fra JWT/cookie
            if (ctx.User?.Identity is not { IsAuthenticated: true })
                return Results.Unauthorized();

            var username = ctx.User.Identity!.Name; // ClaimTypes.Name fra JWT
            if (string.IsNullOrWhiteSpace(username))
                return Results.Unauthorized();
            // Returnér et lille, sikkert udsnit af brugerdata
            var user = await repo.GetByUsernameAsync(username);
            return user is null
                ? Results.Unauthorized()
                : Results.Ok(new { user = new { user.Id, user.Username, user.Role } });
        }).RequireAuthorization();

        // (valgfrit) dev-echo for at se om cookie/Authorization ankommer som forventet virker kun i dev
        if (app.Environment.IsDevelopment())
        {
            g.MapGet("/_echo", (HttpContext ctx) =>
            {
                var hasTokenCookie = ctx.Request.Cookies.ContainsKey("token");
                var bearer = ctx.Request.Headers.Authorization.ToString();
                return Results.Ok(new
                {
                    hasTokenCookie,
                    bearerStartsWith = bearer.StartsWith("Bearer ") ? "Bearer ..." : "(none)"
                });
            }).AllowAnonymous();
        }
    }
}

/// <summary>
/// Request-DTO til <c>POST /auth/register</c>.
/// </summary>
/// <param name="Username">Ønsket brugernavn (skal være unikt).</param>
/// <param name="Password">Brugerens adgangskode i klartekst (hashes på serveren).</param>
/// <returns>Ingen returværdi; DTO'en bruges som input i endpointet.</returns>
/// <remarks>
/// Bruges kun som indlæsningsmodel fra klienten.
/// </remarks>
public sealed record RegisterRequest(string Username, string Password);
/// <summary>
/// Request-DTO til <c>POST /auth/login</c>.
/// </summary>
/// <param name="Username">Brugerens brugernavn.</param>
/// <param name="Password">Brugerens adgangskode i klartekst (verificeres mod hash).</param>
/// <returns>Ingen returværdi; DTO'en bruges som input i endpointet.</returns>
/// <remarks>
/// Ved succes returnerer serveren en <see cref="AuthResponse"/> og sætter evt. en HTTP-only cookie.
/// </remarks>
public sealed record LoginRequest(string Username, string Password);
/// <summary>
/// Svar-DTO fra autentificering (fx login), som indeholder et JWT og basisoplysninger.
/// </summary>
/// <remarks>
/// <c>Token</c> kan bruges som <c>Authorization: Bearer &lt;token&gt;</c>. Serveren kan også udstede en cookie.
/// </remarks>
public sealed class AuthResponse
{
    public string Token { get; set; } = "";
    public string Username { get; set; } = "";
    public string Role { get; set; } = "user";
}
