<Project>
  <PropertyGroup>
    <IncludeSourceRevisionInInformationalVersion>true</IncludeSourceRevisionInInformationalVersion>
    <PublishRepositoryUrl>true</PublishRepositoryUrl>
    <ContinuousIntegrationBuild>true</ContinuousIntegrationBuild>
  </PropertyGroup>

  <ItemGroup>
    <AssemblyAttribute Include="System.Reflection.AssemblyMetadataAttribute">
      <_Parameter1>CommitSha</_Parameter1>
      <_Parameter2>$(SourceRevisionId)</_Parameter2>
    </AssemblyAttribute>
  </ItemGroup>
</Project>
