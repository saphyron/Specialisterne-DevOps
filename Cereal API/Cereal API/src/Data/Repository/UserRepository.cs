// Cereal API/src/Data/Repository/UsersRepository.cs
using CerealAPI.Models;
using Dapper;

namespace CerealAPI.Data.Repository;

/// <summary>
/// Repository til at læse/rette/oprette brugere i databasen.
/// Bruges af auth-flowet til opslag på id/brugernavn samt ved oprettelse.
/// </summary>
/// <remarks>
/// - Wrapper rundt om <see cref="SqlConnectionCeral"/> og Dapper for letvægts dataadgang.
/// - Hver metode åbner en ny DbConnection via factory og sørger for deterministisk dispose med <c>using</c>.
/// - Al SQL er parameteriseret (ingen string-interpolation) for at undgå SQL injection.
/// - Metoder er asynkrone og returnerer <c>Task</c>, Dapper står for mapping til <see cref="User"/>.
/// </remarks>
public sealed class UsersRepository
{
    private readonly SqlConnectionCeral _factory;

    public UsersRepository(SqlConnectionCeral factory)
    {
        _factory = factory;
    }
    /// <summary>
    /// Henter en bruger ud fra dens Id. Returnerer <c>null</c> hvis ingen findes.
    /// </summary>
    /// <param name="id">Primærnøglen (Users.Id).</param>
    /// <returns><see cref="User"/> eller <c>null</c> indpakket i en <see cref="Task{TResult}"/>.</returns>
    /// <remarks>
    /// Kører en SELECT med parameteren <c>@id</c> og mapper første række via Dapper
    /// (<c>QueryFirstOrDefaultAsync</c>). Ingen NOLOCK bruges.
    /// </remarks>
    public async Task<User?> GetByIdAsync(int id)
    {
        const string sql = @"SELECT Id, Username, PasswordHash, Role, CreatedAt
                             FROM dbo.Users
                             WHERE Id = @id";
        // Åbn en frisk DbConnection og sørg for deterministisk dispose
        using var conn = _factory.Create();
        // Parameteriseret query: @id udfyldes af Dapper
        return await conn.QueryFirstOrDefaultAsync<User>(sql, new { id });
    }
    /// <summary>
    /// Henter en bruger ud fra brugernavn. Returnerer <c>null</c> hvis ingen findes.
    /// </summary>
    /// <param name="username">Unikt brugernavn (afhænger af DB-collation ift. case-sensitivity).</param>
    /// <returns><see cref="User"/> eller <c>null</c> indpakket i en <see cref="Task{TResult}"/>.</returns>
    /// <remarks>
    /// Bruger <c>TOP 1</c> for deterministisk resultat hvis der (fejlagtigt) findes dubletter.
    /// </remarks>
    public async Task<User?> GetByUsernameAsync(string username)
    {
        const string sql = @"SELECT TOP 1 Id, Username, PasswordHash, Role, CreatedAt
                             FROM dbo.Users
                             WHERE Username = @username";
        using var conn = _factory.Create();
        return await conn.QueryFirstOrDefaultAsync<User>(sql, new { username });
    }
    /// <summary>
    /// Tjekker om et brugernavn allerede findes.
    /// </summary>
    /// <param name="username">Brugernavn der testes for eksistens.</param>
    /// <returns><c>true</c> hvis der findes mindst én række; ellers <c>false</c>.</returns>
    /// <remarks>
    /// Bruger <c>EXISTS</c> for at undgå unødig dataoverførsel. Returnerer 1/0 fra SQL og
    /// mappes til bool i C#.
    /// </remarks>
    public async Task<bool> UsernameExistsAsync(string username)
    {
        const string sql = @"SELECT CASE WHEN EXISTS(SELECT 1 FROM dbo.Users WHERE Username=@username) THEN 1 ELSE 0 END";
        using var conn = _factory.Create();
        var exists = await conn.ExecuteScalarAsync<int>(sql, new { username });
        return exists == 1;
    }
    /// <summary>
    /// Opretter en ny bruger og returnerer den nye Id.
    /// </summary>
    /// <param name="username">Brugerens brugernavn (forventes at være unikt).</param>
    /// <param name="passwordHash">Hash af brugerens adgangskode (ikke raw password).</param>
    /// <param name="role">Brugerrolle; default er <c>"user"</c>.</param>
    /// <returns>Nyoprettet bruger-Id som <see cref="int"/> indpakket i en <see cref="Task{TResult}"/>.</returns>
    /// <remarks>
    /// Indsætter via parameteriseret INSERT og returnerer <c>SCOPE_IDENTITY()</c> castet til INT.
    /// Antager at password allerede er hashed korrekt på kaldende lag. 
    /// </remarks>
    public async Task<int> CreateAsync(string username, string passwordHash, string role = "user")
    {
        const string sql = @"
INSERT INTO dbo.Users (Username, PasswordHash, Role)
VALUES (@username, @passwordHash, @role);
SELECT CAST(SCOPE_IDENTITY() AS INT);";
        using var conn = _factory.Create();
        // Returnér ny genereret Id via SCOPE_IDENTITY()
        return await conn.ExecuteScalarAsync<int>(sql, new { username, passwordHash, role });
    }
    /// <summary>
    /// Opdaterer adgangskode-hash for en eksisterende bruger.
    /// </summary>
    /// <param name="id">Brugerens Id.</param>
    /// <param name="newHash">Det nye hash (ikke raw password).</param>
    /// <returns>Antal opdaterede rækker (0 eller 1) indpakket i en <see cref="Task{TResult}"/>.</returns>
    /// <remarks>
    /// Simpel <c>UPDATE</c>. Kaldende lag skal sikre korrekt hashing og evt. invalidere sessioner.
    /// </remarks>
    public async Task<int> UpdatePasswordHashAsync(int id, string newHash)
    {
        const string sql = @"UPDATE dbo.Users SET PasswordHash=@newHash WHERE Id=@id";
        using var conn = _factory.Create();
        return await conn.ExecuteAsync(sql, new { id, newHash });
    }
    /// <summary>
    /// Opdaterer en brugers rolle.
    /// </summary>
    /// <param name="id">Brugerens Id.</param>
    /// <param name="role">Ny rolleværdi (fx <c>user</c>/<c>admin</c>).</param>
    /// <returns>Antal opdaterede rækker (0 eller 1) indpakket i en <see cref="Task{TResult}"/>.</returns>
    /// <remarks>
    /// Input valideres ikke her; kaldende lag bør validere gyldige roller og autorisation (RBAC).
    /// </remarks>
    public async Task<int> UpdateRoleAsync(int id, string role)
    {
        const string sql = @"UPDATE dbo.Users SET Role=@role WHERE Id=@id";
        using var conn = _factory.Create();
        return await conn.ExecuteAsync(sql, new { id, role });
    }
}
