// inside your per‑document loop, after you have `root` and `model`...
var invocations = root
  .DescendantNodes()
  .OfType<InvocationExpressionSyntax>();

foreach (var invocation in invocations)
{
    // We only care about member calls: foo.Bar(...)
    if (invocation.Expression is MemberAccessExpressionSyntax memberAccess)
    {
        // Get the type of the expression before the dot: e.g. 'this.Configuration' or '_configuration'
        var receiverType = model.GetTypeInfo(memberAccess.Expression).Type;
        if (receiverType == null)
            continue;

        // Does it *implement* IConfiguration?
        var isConfiguration = receiverType.AllInterfaces
            .Any(i => i.ToDisplayString() == "Microsoft.Extensions.Configuration.IConfiguration")
          || receiverType.ToDisplayString() == "Microsoft.Extensions.Configuration.IConfiguration";

        if (!isConfiguration)
            continue;

        // At this point, it's a call on an IConfiguration instance.
        var methodSymbol = model.GetSymbolInfo(memberAccess).Symbol as IMethodSymbol;
        var methodName = methodSymbol?.Name ?? memberAccess.Name.Identifier.Text;

        // If it's an extension method (e.g. GetSection, Bind, GetValue, etc.), 
        // the same logic applies because the *receiver* is still IConfiguration.

        // Grab the first argument if you want the key/section name:
        string keyArg = null;
        if (invocation.ArgumentList.Arguments.Count > 0 &&
            invocation.ArgumentList.Arguments[0].Expression is LiteralExpressionSyntax lit &&
            lit.IsKind(SyntaxKind.StringLiteralExpression))
        {
            keyArg = lit.Token.ValueText;
        }

        results.Add(new ConfigHit {
            Project = project.Name,
            File    = doc.FilePath,
            Line    = invocation.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
            Type    = "IConfigurationCall",
            Method  = methodName,
            Key     = keyArg
        });
    }
}

