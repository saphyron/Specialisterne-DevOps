// CerealAPI/src/Utils/Security/JwtHelper.cs

/*
*   Taget brug af gammel kode fra tidligere projekter:
*   - Hele Security og login systemet er baseret på kode jeg har brugt i mange projekter.
*   - JWT token generation and validation
*   - HMAC SHA256 signing
*   - Key stretching (SHA256) hvis nøglen er for kort
*   - Understøtter base64:, hex:, rå base64, eller ren tekst som secret
*   - Claims: sub (UserId), unique_name (Username), role (Role)
*   - keyId i header (valgfrit)
*   - Issuer og Audience (valgfrit)
*   - Lifetime (default 8 timer)
*   - Validate token og returnér brugeren (eller null hvis ugyldig)
*   - Bruges i Authz.cs til at validere og slå bruger op i DB
*   - Bruges i AuthEndpoints.cs til login og token-udstedelse
*   - https://github.com/saphyron/C--Backend/tree/main
*/
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace CerealAPI.Utils.Security;
/// <summary>
/// Utility til at udstede og validere JWTs for brugere i API'et.
/// Indeholder hjælp til nøglehåndtering, token-opbygning og -validering.
/// </summary>
/// <remarks>
/// Understøtter hemmeligheder i flere formater (base64:, hex:, rå base64, ren tekst).
/// Signerer med HMAC-SHA256. Mapper standard- og rolleansprings-claims.
/// </remarks>
public static class JwtHelper
{
    /// <summary>
    /// Minimal brugerrepræsentation indlejret i JWT (og retur ved validering).
    /// </summary>
    public sealed class JwtUser
    {
        public int UserId { get; init; }
        public string Username { get; init; } = "";
        public string Role { get; init; } = "";
    }

    /// <summary>
    /// Konverterer en hemmelig nøgle til bytes (med fallback til SHA-256 "stretching" hvis kort).
    /// </summary>
    /// <param name="secret">Hemmeligheden. Kan være <c>base64:</c>, <c>hex:</c>, rå base64 eller ren tekst.</param>
    /// <returns>Byte-array egnet til <see cref="SymmetricSecurityKey"/>.</returns>
    /// <remarks>
    /// Sikrer minimum 256-bit nøglemateriale ved at hash'e input, hvis det er kortere end 32 bytes.
    /// Kaster ved tom/ugyldig hemmelighed.
    /// </remarks>
    private static byte[] GetKeyBytes(string secret)
    {
        if (string.IsNullOrWhiteSpace(secret))
            throw new InvalidOperationException("JWT secret missing.");

        if (secret.StartsWith("base64:", StringComparison.OrdinalIgnoreCase))
            return Convert.FromBase64String(secret.Substring(7));

        if (secret.StartsWith("hex:", StringComparison.OrdinalIgnoreCase))
            return Convert.FromHexString(secret.Substring(4));

        // Rå base64?
        try
        {
            var raw = Convert.FromBase64String(secret);
            return raw.Length >= 32 ? raw : SHA256.HashData(raw);
        }
        catch { /* falder tilbage til UTF-8 */ }

        var utf8 = Encoding.UTF8.GetBytes(secret);
        return utf8.Length >= 32 ? utf8 : SHA256.HashData(utf8);
    }
    /// <summary>
    /// Opretter et signeret adgangstoken for en given bruger.
    /// </summary>
    /// <param name="u">Brugeroplysninger (Id, brugernavn, rolle) til claims.</param>
    /// <param name="secret">Signing secret (understøtter base64:/hex:/rå/tekst).</param>
    /// <param name="keyId">Valgfri key-id (kid) til header; bruges til nøgle-rotation.</param>
    /// <param name="lifetime">Gyldighedsperiode. Default er 8 timer.</param>
    /// <param name="issuer">Valgfri issuer-claim.</param>
    /// <param name="audience">Valgfri audience-claim.</param>
    /// <returns>Serieliseret JWT som streng.</returns>
    /// <remarks>
    /// Indsætter claims: <c>sub</c> (UserId), <c>unique_name</c>/<c>name</c> (Username) og <c>role</c>.
    /// Tilføjer <c>kid</c> i header (default "v1" hvis tomt).
    /// </remarks>
    public static string CreateAccessToken(
        JwtUser u,
        string secret,
        string keyId,
        TimeSpan? lifetime = null,
        string? issuer = null,
        string? audience = null)
    {
        var key   = new SymmetricSecurityKey(GetKeyBytes(secret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        // Byg minimale claims til autorisation i API'et
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, u.UserId.ToString()),
            new Claim(JwtRegisteredClaimNames.UniqueName, u.Username),
            new Claim(ClaimTypes.Name, u.Username),
            new Claim(ClaimTypes.Role, u.Role ?? "")
        };

        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            notBefore: now,
            expires: now.Add(lifetime ?? TimeSpan.FromHours(8)),
            signingCredentials: creds
        );
        token.Header["kid"] = string.IsNullOrWhiteSpace(keyId) ? "v1" : keyId;

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
    /// <summary>
    /// Validerer et JWT og udtrækker brugerclaims, hvis token er gyldigt.
    /// </summary>
    /// <param name="token">Indkommende JWT.</param>
    /// <param name="secret">Signing secret (samme formatregler som ved oprettelse).</param>
    /// <param name="issuer">Forventet issuer (valideres kun hvis angivet).</param>
    /// <param name="audience">Forventet audience (valideres kun hvis angivet).</param>
    /// <returns>
    /// <see cref="JwtUser"/> med <c>UserId</c>, <c>Username</c> og <c>Role</c> ved succes; ellers <c>null</c>.
    /// </returns>
    /// <remarks>
    /// Validerer signatur, (eventuelt) issuer/audience, udløbstid og notBefore.
    /// Returnerer kun de claims, som resten af app’en har brug for.
    /// </remarks>
    public static JwtUser? Validate(string token, string secret, string? issuer = null, string? audience = null)
    {
        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        var key     = new SymmetricSecurityKey(GetKeyBytes(secret));

        try
        {
            var parms = new TokenValidationParameters
            {
                ValidateIssuer = !string.IsNullOrWhiteSpace(issuer),
                ValidIssuer    = issuer,
                ValidateAudience = !string.IsNullOrWhiteSpace(audience),
                ValidAudience    = audience,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = key,
                ClockSkew = TimeSpan.FromMinutes(2)
            };

            var principal = handler.ValidateToken(token, parms, out _);
            // Udfolder relevante claims (fald tilbage til flere muligheder)
            var idStr = principal.FindFirstValue(JwtRegisteredClaimNames.Sub)
                       ?? principal.FindFirstValue(ClaimTypes.NameIdentifier)
                       ?? "0";
            _ = int.TryParse(idStr, out var uid);

            var username = principal.FindFirstValue(JwtRegisteredClaimNames.UniqueName)
                         ?? principal.FindFirstValue(ClaimTypes.Name)
                         ?? principal.Identity?.Name
                         ?? "";

            var role = principal.FindFirstValue(ClaimTypes.Role) ?? "";

            return new JwtUser { UserId = uid, Username = username, Role = role };
        }
        catch
        {
            // Ugyldigt token: signatur/claims/tidspunkt mv.
            return null;
        }
    }
}
