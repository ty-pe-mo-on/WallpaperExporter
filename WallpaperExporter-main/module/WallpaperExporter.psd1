@{
    RootModule           = 'WallpaperExporter.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '6f8a9b1c-2d3e-4f5a-8b6c-9d0e1f2a3b4c'
    Author               = 'WallpaperExporter contributors'
    CompanyName          = 'WallpaperExporter'
    Copyright            = '(c) WallpaperExporter contributors. MIT License.'
    Description          = 'Extract only the main artwork images from Wallpaper Engine (Steam) wallpapers into one flat folder.'
    PowerShellVersion    = '5.1'
    FunctionsToExport    = @('Export-WallpaperImages')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('WallpaperEngine', 'RePKG', 'wallpaper', 'image', 'extract')
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}
