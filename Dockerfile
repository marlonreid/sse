using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Build.Locator;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.MSBuild;

namespace ConfigScanner
{
    class ConfigHit
    {
        public string Project;
        public string File;
        public int Line;
        public string Category;     // IConfiguration, Options, Provider, etc.
        public string Method;       // e.g. GetValue, Value, .Bind
        public string Key;          // config key or null
    }

    class Program
    {
        static async Task Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.Error.WriteLine("Usage: dotnet run -- <path-to-solution-folder>");
                return;
            }

            MSBuildLocator.RegisterDefaults();
            using var workspace = MSBuildWorkspace.Create();
            var solutions = Directory.GetFiles(args[0], "*.sln", SearchOption.AllDirectories);
            var results = new List<ConfigHit>();

            foreach (var sln in solutions)
            {
                Console.WriteLine($"Loading solution {Path.GetFileName(sln)}...");
                var solution = await workspace.OpenSolutionAsync(sln);

                foreach (var project in solution.Projects)
                foreach (var doc in project.Documents)
                {
                    var root = await doc.GetSyntaxRootAsync();
                    if (root == null) continue;

                    var model = await doc.GetSemanticModelAsync();
                    if (model == null) continue;

                    ScanElementAccess(root, model, project.Name, doc.FilePath, results);
                    ScanInvocations(root, model, project.Name, doc.FilePath, results);
                    ScanMemberAccess(root, model, project.Name, doc.FilePath, results);
                    ScanOptionsUsage(root, model, project.Name, doc.FilePath, results);
                    ScanProviderRegistrations(root, model, project.Name, doc.FilePath, results);
                }
            }

            // Output CSV
            using var writer = new StreamWriter("config-discovery.csv");
            writer.WriteLine("Project,File,Line,Category,Method,Key");
            foreach (var hit in results)
                writer.WriteLine($"{hit.Project},{hit.File},{hit.Line},{hit.Category},{hit.Method},{hit.Key}");

            Console.WriteLine("Scan complete. See config-discovery.csv");
        }

        static void ScanElementAccess(SyntaxNode root, SemanticModel model, string project, string file, List<ConfigHit> results)
        {
            var elements = root.DescendantNodes().OfType<ElementAccessExpressionSyntax>();
            foreach (var ea in elements)
            {
                var type = model.GetTypeInfo(ea.Expression).Type;
                if (!Implements(model, type, "Microsoft.Extensions.Configuration.IConfiguration"))
                    continue;

                var key = GetStringConstant(ea.ArgumentList.Arguments[0].Expression, model);
                results.Add(new ConfigHit {
                    Project = project,
                    File = file,
                    Line = ea.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
                    Category = "IConfiguration",
                    Method = "Indexer",
                    Key = key
                });
            }
        }

        static void ScanInvocations(SyntaxNode root, SemanticModel model, string project, string file, List<ConfigHit> results)
        {
            var calls = root.DescendantNodes().OfType<InvocationExpressionSyntax>();
            foreach (var inv in calls)
            {
                if (!(inv.Expression is MemberAccessExpressionSyntax ma)) continue;

                var recvType = model.GetTypeInfo(ma.Expression).Type;
                // IConfiguration calls
                if (Implements(model, recvType, "Microsoft.Extensions.Configuration.IConfiguration"))
                {
                    var method = ma.Name.Identifier.Text;
                    var key = inv.ArgumentList.Arguments.Count > 0
                        ? GetStringConstant(inv.ArgumentList.Arguments[0].Expression, model)
                        : null;

                    results.Add(new ConfigHit {
                        Project = project,
                        File = file,
                        Line = inv.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
                        Category = "IConfiguration",
                        Method = method,
                        Key = key
                    });
                    continue;
                }
            }
        }

        static void ScanMemberAccess(SyntaxNode root, SemanticModel model, string project, string file, List<ConfigHit> results)
        {
            var members = root.DescendantNodes().OfType<MemberAccessExpressionSyntax>();
            foreach (var ma in members)
            {
                var recvType = model.GetTypeInfo(ma.Expression).Type;
                if (Implements(model, recvType, "Microsoft.Extensions.Options.IOptions`1") ||
                    Implements(model, recvType, "Microsoft.Extensions.Options.IOptionsMonitor`1") )
                {
                    var prop = ma.Name.Identifier.Text;
                    if (prop == "Value" || prop == "CurrentValue")
                    {
                        results.Add(new ConfigHit {
                            Project = project,
                            File = file,
                            Line = ma.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
                            Category = "Options",
                            Method = prop,
                            Key = null
                        });
                    }
                }
            }
        }

        static void ScanOptionsUsage(SyntaxNode root, SemanticModel model, string project, string file, List<ConfigHit> results)
        {
            // invocations on IOptions*, e.g. Get("name")
            var calls = root.DescendantNodes().OfType<InvocationExpressionSyntax>();
            foreach (var inv in calls)
            {
                if (!(inv.Expression is MemberAccessExpressionSyntax ma)) continue;
                var recvType = model.GetTypeInfo(ma.Expression).Type;
                if (Implements(model, recvType, "Microsoft.Extensions.Options.IOptionsMonitor`1"))
                {
                    var method = ma.Name.Identifier.Text;
                    var key = inv.ArgumentList.Arguments.Count > 0
                        ? GetStringConstant(inv.ArgumentList.Arguments[0].Expression, model)
                        : null;

                    results.Add(new ConfigHit {
                        Project = project,
                        File = file,
                        Line = inv.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
                        Category = "Options",
                        Method = method,
                        Key = key
                    });
                }
            }
        }

        static void ScanProviderRegistrations(SyntaxNode root, SemanticModel model, string project, string file, List<ConfigHit> results)
        {
            var calls = root.DescendantNodes().OfType<InvocationExpressionSyntax>();
            foreach (var inv in calls)
            {
                if (!(inv.Expression is MemberAccessExpressionSyntax ma)) continue;
                var recvType = model.GetTypeInfo(ma.Expression).Type;
                if (recvType?.ToDisplayString().Contains("ConfigurationBuilder") == true)
                {
                    var provider = ma.Name.Identifier.Text;
                    results.Add(new ConfigHit {
                        Project = project,
                        File = file,
                        Line = inv.GetLocation().GetLineSpan().StartLinePosition.Line + 1,
                        Category = "Provider",
                        Method = provider,
                        Key = null
                    });
                }
            }
        }

        static bool Implements(SemanticModel model, ITypeSymbol type, string iface)
        {
            if (type == null) return false;
            var all = new[] { type }.Concat(type.AllInterfaces);
            return all.Any(i => i.OriginalDefinition.ToDisplayString().StartsWith(iface));
        }

        static string GetStringConstant(ExpressionSyntax expr, SemanticModel model)
        {
            if (expr is LiteralExpressionSyntax lit && lit.IsKind(SyntaxKind.StringLiteralExpression))
                return lit.Token.ValueText;

            var constVal = model.GetConstantValue(expr);
            if (constVal.HasValue && constVal.Value is string s)
                return s;

            return null;
        }
    }
}
