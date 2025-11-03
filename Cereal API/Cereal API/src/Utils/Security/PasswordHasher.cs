// CerealAPI/src/Utils/Security/PasswordHasher.cs
using System.Security.Cryptography;
using System.Text;

/*
*   Taget brug af gammel kode fra tidligere projekter:
*   - https://github.com/saphyron/C--Backend/tree/main
*/

namespace CerealAPI.Utils.Security;
/// <summary>
/// PBKDF2-baseret password-hasher/validator til brugerkonti i API'et.
/// Genererer salts og lagrer hash i et simpelt, læsbart format.
/// </summary>
/// <remarks>
/// Format: <c>pbkdf2$&lt;iterations&gt;$&lt;salt-base64&gt;$&lt;hash-base64&gt;$HMACSHA256</c>.
/// Bruger PBKDF2-HMACSHA256, 16 bytes salt og 32 bytes nøgle, med 120.000 iterationer.
/// </remarks>
public static class PasswordHasher
{
    // Parametre for PBKDF2
    private const int Iterations = 120_000;
    private const int SaltSize = 16;
    private const int KeySize = 32;
    private const string Prf = "HMACSHA256";
    private const string Prefix = "pbkdf2";
    /// <summary>
    /// Hasher et plaintext password med PBKDF2 og tilfældigt salt.
    /// </summary>
    /// <param name="password">Brugerens plaintext password.</param>
    /// <returns>
    /// En streng i formatet <c>pbkdf2$iterations$saltBase64$hashBase64$HMACSHA256</c>.
    /// </returns>
    /// <remarks>
    /// Salt genereres kryptografisk og output kan gemmes direkte i databasen.
    /// </remarks>
    public static string Hash(string password)
    {
        if (string.IsNullOrEmpty(password)) throw new ArgumentException("Empty password.");
        // Generér kryptografisk salt og afled nøgle
        Span<byte> salt = stackalloc byte[SaltSize];
        RandomNumberGenerator.Fill(salt);

        var key = Rfc2898DeriveBytes.Pbkdf2(password, salt.ToArray(), Iterations, HashAlgorithmName.SHA256, KeySize);
        return $"{Prefix}${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(key)}${Prf}";
    }
    /// <summary>
    /// Verificerer om et givet plaintext password matcher en lagret PBKDF2-hash.
    /// </summary>
    /// <param name="password">Indtastet plaintext password.</param>
    /// <param name="encoded">Lagringsformat fra <see cref="Hash(string)"/>.</param>
    /// <returns><c>true</c> hvis password matcher hash'en; ellers <c>false</c>.</returns>
    /// <remarks>
    /// Validerer format, genskaber hash med lagrede parametre og sammenligner konstant-tidsmæssigt.
    /// </remarks>
    public static bool Verify(string password, string encoded)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(password) || string.IsNullOrWhiteSpace(encoded)) return false;
            // Parse lagret format og udlæs parametre
            var parts = encoded.Split('$');
            if (parts.Length < 5 || parts[0] != Prefix) return false;

            int iterations = int.Parse(parts[1]);
            byte[] salt = Convert.FromBase64String(parts[2]);
            byte[] hash = Convert.FromBase64String(parts[3]);
            // Genskab hash med samme parametre og sammenlign i konstant tid
            var calc = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, hash.Length);
            return CryptographicOperations.FixedTimeEquals(calc, hash);
        }
        catch { return false; }
    }
    /// <summary>
    /// Heuristik: ligner strengen en PBKDF2-hash fra denne helper.
    /// </summary>
    /// <param name="value">Strengen der undersøges.</param>
    /// <returns><c>true</c> hvis strengen starter med <c>pbkdf2$</c>; ellers <c>false</c>.</returns>
    /// <remarks>
    /// Brugbar til at afgøre om ældre (klartekst) passwords skal migreres ved login.
    /// </remarks>
    public static bool LooksHashed(string? value)
        => !string.IsNullOrWhiteSpace(value) && value.StartsWith($"{Prefix}$", StringComparison.Ordinal);
}
