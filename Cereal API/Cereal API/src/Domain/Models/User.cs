// src/Domain/Models/User.cs
namespace CerealAPI.Models
{
    /// <summary>
    /// Domænemodel for en bruger, som afspejler rækken i <c>dbo.Users</c>.
    /// Bruges af Dapper til materialisering af database-rows.
    /// </summary>
    /// <remarks>
    /// <para><c>PasswordHash</c> indeholder en hash (ikke klartekst) og må aldrig logges.</para>
    /// <para><c>Role</c> default'er til <c>"user"</c> og kan opdateres af admins.</para>
    /// <para><c>CreatedAt</c> sættes i databasen (f.eks. via DEFAULT/GETUTCDATE()).</para>
    /// </remarks>
    public sealed class User
    {
        public int Id { get; set; }
        public string Username { get; set; } = default!;
        public string PasswordHash { get; set; } = default!;
        public string Role { get; set; } = "user";
        public DateTime CreatedAt { get; set; }
    }
    /// <summary>
    /// Request-DTO til <c>POST /auth/register</c>.
    /// Indeholder de felter klienten skal sende for at oprette en ny bruger.
    /// </summary>
    /// <remarks>
    /// Serveren validerer, at <c>Username</c>/<c>Password</c> er udfyldt og at brugernavn er unikt.
    /// Password hashes før persistens; klartekst password gemmes aldrig.
    /// </remarks>
    public sealed class RegisterRequest
    {
        public string Username { get; set; } = default!;
        public string Password { get; set; } = default!;
    }
    /// <summary>
    /// Request-DTO til <c>POST /auth/login</c>.
    /// Bruges til at sende legitimationsoplysninger for login.
    /// </summary>
    /// <remarks>
    /// Ved succes returnerer API'et en <see cref="AuthResponse"/> og kan sætte en <c>token</c>-cookie (HTTPS),
    /// samt tillader brug af Bearer JWT i Authorization-headeren.
    /// </remarks>
    public sealed class LoginRequest
    {
        public string Username { get; set; } = default!;
        public string Password { get; set; } = default!;
    }
    /// <summary>
    /// Svar-DTO fra autentificering (fx <c>POST /auth/login</c>).
    /// Indeholder et JWT samt bekvemmelighedsfelter om brugeren.
    /// </summary>
    /// <remarks>
    /// <para><c>Token</c> er et JWT, der kan bruges som <c>Authorization: Bearer &lt;token&gt;</c>.</para>
    /// <para>Serveren kan også udstede en HTTP-only cookie med samme token for cookie-baseret auth.</para>
    /// </remarks>
    public sealed class AuthResponse
    {
        public string Token { get; set; } = default!;
        public string Username { get; set; } = default!;
        public string Role { get; set; } = default!;
    }
}