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
