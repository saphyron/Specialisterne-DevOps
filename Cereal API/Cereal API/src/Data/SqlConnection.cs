// src/Data/SqlConnection.cs
using Microsoft.Data.SqlClient;
using System.Data;

namespace CerealAPI.Data;
/// <summary>
/// Simpelt “factory”-objekt som ud fra en connection string kan udlevere nye
/// databaseforbindelser til SQL Server.
/// </summary>
/// <remarks>
/// Indkapsler <see cref="SqlConnection"/> bag <see cref="IDbConnection"/> for at gøre
/// afhængigheder nemmere at teste og udskifte. Hver kald til <see cref="Create"/> returnerer
/// en ny, endnu ikke åbnet forbindelse, som kalderen selv skal åbne og dispose via <c>using</c>.
/// </remarks>
public class SqlConnectionCeral
{
    private readonly string _connString;
    public SqlConnectionCeral(string connString) => _connString = connString;

    public IDbConnection Create() => new SqlConnection(_connString);
}