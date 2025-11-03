// src/Utils/HttpHelpers.cs
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text;
using CerealAPI.Models;

namespace CerealAPI.Utils
{
    /// <summary>
    /// Hjælpefunktioner til at bygge URL-stier og querystrings, samt typed HTTP-kald
    /// til Cereal-endpoints. Samler gentagne URL-operationer ét sted.
    /// </summary>
    /// <remarks>
    /// Metoderne håndterer korrekt URL-encoding af path-segmenter og queryparametre,
    /// og sikrer forudsigelig sammensætning af basestier (ingen dobbelte skråstreger).
    /// De to HTTP-helpers (PUT/DELETE) bygger sikre absolutte <see cref="Uri"/> ud fra en baseadresse.
    /// </remarks>
    public static class HttpHelpers
    {
        /// <summary>
        /// URL-encoder et path-segment (fx et produktnavn) så specialtegn er sikre i stien.
        /// </summary>
        /// <param name="segment">Rå tekst der skal bruges som et enkelt path-segment.</param>
        /// <returns>URL-encodet segment (aldrig null; tom streng hvis input er null).</returns>
        /// <remarks>
        /// Bruger <see cref="Uri.EscapeDataString(string)"/> som er egnet til segmenter
        /// (i modsætning til hele URLs). Anvend før du sætter værdier ind i en sti.
        /// </remarks>
        public static string EncodePathSegment(string segment)
            => Uri.EscapeDataString(segment ?? string.Empty);

        /// <summary>
        /// Kombinerer vilkårlige path-segmenter til en enkelt sti med præcis én
        /// skråstreg mellem segmenter (uden dobbelte skråstreger).
        /// </summary>
        /// <param name="segments">En eller flere segmenter, fx "cereals", "{name}", ...</param>
        /// <returns>En sammensat sti der starter med <c>/</c> og har korrekte separatorer.</returns>
        /// <remarks>
        /// Fjerner leading <c>/</c> på de enkelte segmenter for at undgå <c>//</c> i output.
        /// Overlader ikke-ASCII og specialtegn til kalderen (brug <see cref="EncodePathSegment"/> pr. segment).
        /// </remarks>
        public static string CombinePath(params string[] segments)
        {
            var sb = new StringBuilder();
            foreach (var raw in segments)
            {
                if (string.IsNullOrEmpty(raw)) continue;
                // Sørg for én enkelt '/' mellem segmenter
                if (sb.Length == 0 || sb[^1] != '/')
                    sb.Append('/');

                // Fjern evt. leading '/' i segment for at undgå dobbelte skråstreger
                var seg = raw[0] == '/' ? raw.Substring(1) : raw;
                sb.Append(seg);
            }
            return sb.ToString();
        }

        /// <summary>
        /// Bygger en querystring ud fra et key/value‐sæt og URL-encoder både nøgler og værdier.
        /// </summary>
        /// <param name="query">Opslagstabel med parameternavne og -værdier. Null/tom giver tom streng.</param>
        /// <returns>Querystring der starter med <c>?</c>, eller tom streng ved ingen parametre.</returns>
        /// <remarks>
        /// Null-værdier konverteres til tom tekst. Metoden antager simple værdier; komplekse
        /// typer bør serialiseres til string på forhånd.
        /// </remarks>
        public static string BuildQuery(IDictionary<string, object?>? query)
        {
            if (query == null || query.Count == 0) return string.Empty;
            var sb = new StringBuilder("?");
            bool first = true;
            foreach (var kv in query)
            {
                if (!first) sb.Append('&'); else first = false;
                sb.Append(Uri.EscapeDataString(kv.Key));
                sb.Append('=');
                sb.Append(Uri.EscapeDataString(kv.Value?.ToString() ?? string.Empty));
            }
            return sb.ToString();
        }

        /// <summary>
        /// Bygger stinøglen for en cereal-række baseret på name/mfr/type (alle tre URL-encodes).
        /// </summary>
        /// <param name="name">Cereal-navn.</param>
        /// <param name="mfr">Producentkode (K, G, ...).</param>
        /// <param name="type">Cereal-type (fx C).</param>
        /// <returns>Relativ sti: <c>/cereals/{name}/{mfr}/{type}</c> med korrekt encoding.</returns>
        /// <remarks>
        /// Bruges når endpoints adresserer en række via dens naturlige nøgle fremfor ID.
        /// </remarks>
        public static string CerealKeyPath(string name, string mfr, string type)
            => CombinePath("cereals",
                           EncodePathSegment(name),
                           EncodePathSegment(mfr),
                           EncodePathSegment(type));

        /// <summary>
        /// Sender et PUT-kald til <c>/cereals/{name}/{mfr}/{type}</c> med en opdateret <see cref="Cereal"/> i JSON-body.
        /// </summary>
        /// <param name="http">En initialiseret <see cref="HttpClient"/>.</param>
        /// <param name="baseAddress">Absolut base-URL (fx <c>https://localhost:7257/</c>).</param>
        /// <param name="cerealKey">Objekt der indeholder nøglefelterne (name/mfr/type) til stien.</param>
        /// <param name="update">Objekt med felter der ønskes opdateret.</param>
        /// <returns>HTTP-svar fra serveren.</returns>
        /// <remarks>
        /// Metoden konstruerer en absolut <see cref="Uri"/> ud fra basen og den relative nøglesti,
        /// og bruger <see cref="HttpClientJsonExtensions.PutAsJsonAsync{TValue}(HttpClient, Uri, TValue, System.Text.Json.JsonSerializerOptions?, System.Threading.CancellationToken)"/>
        /// til at serialisere <paramref name="update"/>.
        /// </remarks>
        public static async System.Threading.Tasks.Task<HttpResponseMessage>
            PutCerealAsync(this HttpClient http, string baseAddress, Cereal cerealKey, Cereal update)
        {
            // Byg absolut URI for PUT
            var path = CerealKeyPath(cerealKey.name, cerealKey.mfr, cerealKey.type);
            var uri = new Uri(new Uri(baseAddress, UriKind.Absolute), path);
            return await http.PutAsJsonAsync(uri, update);
        }

        /// <summary>
        /// Sender et DELETE-kald til <c>/cereals/{name}/{mfr}/{type}</c>.
        /// </summary>
        /// <param name="http">En initialiseret <see cref="HttpClient"/>.</param>
        /// <param name="baseAddress">Absolut base-URL (fx <c>https://localhost:7257/</c>).</param>
        /// <param name="name">Cereal-navn.</param>
        /// <param name="mfr">Producentkode.</param>
        /// <param name="type">Cereal-type.</param>
        /// <returns>HTTP-svar fra serveren.</returns>
        /// <remarks>
        /// Metoden URL-encoder nøglefelterne og sammensætter en absolut <see cref="Uri"/>
        /// før den udfører <see cref="HttpClient.DeleteAsync(Uri)"/>.
        /// </remarks>
        public static async System.Threading.Tasks.Task<HttpResponseMessage>
            DeleteCerealAsync(this HttpClient http, string baseAddress, string name, string mfr, string type)
        {
            var path = CerealKeyPath(name, mfr, type);
            var uri = new Uri(new Uri(baseAddress, UriKind.Absolute), path);
            return await http.DeleteAsync(uri);
        }
    }
}
