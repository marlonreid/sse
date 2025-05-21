// Program.cs
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.MSBuild;
using System.Text.Json;

var workspace = MSBuildWorkspace.Create();
Console.WriteLine("Loading solution...");
var solution = await workspace.OpenSolutionAsync("YourSolution.sln");

var allConfigAccesses = new List<ConfigAccess>();

foreach (var project in solution.Projects)
{
    foreach (var doc in project.Documents)
    {
        var tree = await doc.GetSyntaxTreeAsync();
        var model = await doc.GetSemanticModelAsync();
        var root = await tree.GetRootAsync();

        var invocations = root.DescendantNodes().OfType<InvocationExpressionSyntax>();
        var indexers = root.DescendantNodes().OfType<ElementAccessExpressionSyntax>();

        foreach (var invocation in invocations)
        {
            if (invocation.Expression is MemberAccessExpressionSyntax memberAccess)
            {
                var method = memberAccess.Name.Identifier.Text;
                if (method == "GetSection" || method == "GetValue" || method == "Bind")
                {
                    var keys = GetChainedSections(invocation, model);
                    allConfigAccesses.Add(new ConfigAccess
                    {
                        Keys = keys,
                        AccessType = method,
                        File = doc.FilePath,
                        Line = invocation.GetLocation().GetLineSpan().StartLinePosition.Line + 1
                    });
                }
            }
        }

        foreach (var indexer in indexers)
        {
            if (indexer.Expression is IdentifierNameSyntax ident &&
                (ident.Identifier.Text == "Configuration" || ident.Identifier.Text == "config"))
            {
                var arg = indexer.ArgumentList.Arguments.FirstOrDefault()?.Expression;
                if (arg is LiteralExpressionSyntax literal)
                {
                    allConfigAccesses.Add(new ConfigAccess
                    {
                        Keys = new List<string> { literal.Token.ValueText },
                        AccessType = "Indexer",
                        File = doc.FilePath,
                        Line = indexer.GetLocation().GetLineSpan().StartLinePosition.Line + 1
                    });
                }
            }
        }
    }
}

File.WriteAllText("config-accesses.json", JsonSerializer.Serialize(allConfigAccesses, new JsonSerializerOptions
{
    WriteIndented = true
}));

Console.WriteLine("Done. Results written to config-accesses.json");

// Helper types and methods
record ConfigAccess
{
    public List<string> Keys { get; set; } = new();
    public string AccessType { get; set; } = "Unknown";
    public string File { get; set; } = "";
    public int Line { get; set; }
}

List<string> GetChainedSections(ExpressionSyntax expr, SemanticModel model)
{
    var keys = new List<string>();

    while (expr is InvocationExpressionSyntax invocation)
    {
        if (invocation.Expression is MemberAccessExpressionSyntax memberAccess &&
            memberAccess.Name.Identifier.Text == "GetSection")
        {
            var arg = invocation.ArgumentList.Arguments.FirstOrDefault()?.Expression;
            if (arg is LiteralExpressionSyntax literal)
            {
                keys.Insert(0, literal.Token.ValueText);
            }
            expr = memberAccess.Expression;
        }
        else
        {
            break;
        }
    }

    return keys;
}
