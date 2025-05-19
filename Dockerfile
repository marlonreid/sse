static bool IsOptionsInterface(ITypeSymbol type)
{
    if (type == null) return false;

    // Look at the type itself and all its interfaces:
    var all = new[] { type }.Concat(type.AllInterfaces);

    foreach (var t in all)
    {
        if (t is INamedTypeSymbol named
            && named.IsGenericType
            && (
                named.ConstructedFrom.ToDisplayString() == "Microsoft.Extensions.Options.IOptions<TOptions>"
             || named.ConstructedFrom.ToDisplayString() == "Microsoft.Extensions.Options.IOptionsMonitor<TOptions>"
             || named.ConstructedFrom.ToDisplayString() == "Microsoft.Extensions.Options.IOptionsSnapshot<TOptions>"
             || named.ConstructedFrom.ToDisplayString() == "Microsoft.Extensions.Options.IOptionsFactory<TOptions>"
             || named.ConstructedFrom.ToDisplayString() == "Microsoft.Extensions.Options.IOptionsMonitorCache<TOptions>"
            ))
        {
            return true;
        }
    }
    return false;
}











// in your per‑document loop, after you have `root` and `model`...
var ctors = root.DescendantNodes()
    .OfType<ConstructorDeclarationSyntax>();

foreach (var ctor in ctors)
{
    foreach (var param in ctor.ParameterList.Parameters)
    {
        var paramType = model.GetTypeInfo(param.Type).Type;
        if (IsOptionsInterface(paramType))
        {
            results.Add(new ConfigHit {
                Project = project.Name,
                File    = doc.FilePath,
                Line    = param.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
                Type    = "OptionsInjection",
                Method  = ctor.Identifier.Text,
                Key     = paramType.ToDisplayString()
            });
        }
    }
}





var invocations = root
    .DescendantNodes()
    .OfType<InvocationExpressionSyntax>();

foreach (var invocation in invocations)
{
    if (!(invocation.Expression is MemberAccessExpressionSyntax memberAccess))
        continue;

    var receiverType = model.GetTypeInfo(memberAccess.Expression).Type;
    if (!IsOptionsInterface(receiverType))
        continue;

    // e.g. options.Value, monitor.CurrentValue, options.Get("MyNamed")
    var methodName = memberAccess.Name.Identifier.Text;
    string keyArg = null;
    if (invocation.ArgumentList.Arguments.Count > 0
        && invocation.ArgumentList.Arguments[0].Expression is LiteralExpressionSyntax lit
        && lit.IsKind(SyntaxKind.StringLiteralExpression))
    {
        keyArg = lit.Token.ValueText;
    }

    results.Add(new ConfigHit {
        Project = project.Name,
        File    = doc.FilePath,
        Line    = invocation.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
        Type    = "OptionsCall",
        Method  = methodName,
        Key     = keyArg
    });
}











var memberAccesses = root.DescendantNodes()
    .OfType<MemberAccessExpressionSyntax>();

foreach (var ma in memberAccesses)
{
    var receiverType = model.GetTypeInfo(ma.Expression).Type;
    if (!IsOptionsInterface(receiverType))
        continue;

    var prop = ma.Name.Identifier.Text;
    if (prop == "Value" || prop == "CurrentValue")
    {
        results.Add(new ConfigHit {
            Project = project.Name,
            File    = doc.FilePath,
            Line    = ma.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
            Type    = "OptionsProperty",
            Method  = prop,
            Key     = null
        });
    }
}
