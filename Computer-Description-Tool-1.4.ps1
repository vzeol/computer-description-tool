$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$null = $null

& {
$null = Add-Type -AssemblyName System.Windows.Forms
$null = Add-Type -AssemblyName System.Drawing

############################################
# Thème
############################################

$accentColor      = [System.Drawing.Color]::FromArgb(0,103,192)
$accentColorHover = [System.Drawing.Color]::FromArgb(0,86,163)
$bgColor          = [System.Drawing.Color]::FromArgb(243,243,243)
$textColor        = [System.Drawing.Color]::FromArgb(51,51,51)
$baseFont         = New-Object System.Drawing.Font("Segoe UI", 9)

# Fenêtre
$form = New-Object System.Windows.Forms.Form
$form.Text = "Computer Description Tool"
$form.ClientSize = New-Object System.Drawing.Size(540,540)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(460,420)
$form.AutoSize = $false
$form.BackColor = $bgColor
$form.ForeColor = $textColor
$form.Font = $baseFont

# Bandeau d'en-tête
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = 'Top'
$pnlHeader.Height = 50
$pnlHeader.BackColor = $accentColor
$form.Controls.Add($pnlHeader)

$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = "Gestion des descriptions de postes"
$lblHeader.ForeColor = [System.Drawing.Color]::White
$lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$lblHeader.AutoSize = $true
$lblHeader.Location = "20,12"
$pnlHeader.Controls.Add($lblHeader)

# StatusBar
$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusBar.SizingGrip = $false
$statusBar.ShowItemToolTips = $true
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Prêt"
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
$statusBar.Items.Add($statusLabel)
$form.Controls.Add($statusBar)

# ProgressBar
$progressBar = New-Object System.Windows.Forms.ToolStripProgressBar
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Visible = $false
$statusBar.Items.Add($progressBar)

# Rappel du compte et du domaine (à droite de la barre de statut)
$lblSession = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusBar.Items.Add($lblSession)

# Tooltips (explications au survol)
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 10000
$toolTip.InitialDelay = 400
$toolTip.ReshowDelay = 100
$toolTip.ShowAlways = $true

# Label PC
$lblPC = New-Object System.Windows.Forms.Label
$lblPC.Text = "Nom du PC :"
$lblPC.Location = "20,70"
$lblPC.AutoSize = $true
$form.Controls.Add($lblPC)

# Champs PC
$txtPC = New-Object System.Windows.Forms.TextBox
$txtPC.Location = "130,67"
$txtPC.Width = 180
$txtPC.Font = $baseFont
$txtPC.Anchor = 'Top,Left,Right'
$form.Controls.Add($txtPC)

# === Prérequis : DC ou poste du domaine + compte admin du domaine ===
function Test-Prerequis {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()

    # Groupes du jeton, y compris ceux filtrés par l'UAC (session non élevée)
    $typesSid = @(
        [System.Security.Claims.ClaimTypes]::GroupSid,
        [System.Security.Claims.ClaimTypes]::DenyOnlySid
    )
    $sids = @($id.Claims | Where-Object { $typesSid -contains $_.Type } | ForEach-Object { $_.Value })

    # Admins du domaine (RID 512) ou Administrateurs de l'entreprise (RID 519)
    $sidAdminsDomaine = "$($id.User.AccountDomainSid)-512"
    $estAdmin = ($sids -contains $sidAdminsDomaine) -or (@($sids -match '^S-1-5-21-\d+-\d+-\d+-519$').Count -gt 0)

    [PSCustomObject]@{
        Domaine    = [bool]$cs.PartOfDomain
        NomDomaine = $cs.Domain
        EstDC      = $cs.DomainRole -ge 4
        Admin      = $estAdmin
        Compte     = $id.Name
        ModuleAD   = [bool](Get-Module -ListAvailable -Name ActiveDirectory)
    }
}

$prerequis = Test-Prerequis
$script:PrerequisOK = $prerequis.Domaine -and $prerequis.Admin -and $prerequis.ModuleAD

# === Auto-complétion AD ===
if ($script:PrerequisOK) {
    try {
        $null = Import-Module ActiveDirectory -ErrorAction Stop

        $PCList = Get-ADComputer -Filter * | Select-Object -ExpandProperty Name

        $autoSource = New-Object System.Windows.Forms.AutoCompleteStringCollection
        $autoSource.AddRange($PCList)

        $txtPC.AutoCompleteMode = 'SuggestAppend'
        $txtPC.AutoCompleteSource = 'CustomSource'
        $txtPC.AutoCompleteCustomSource = $autoSource
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
        "Auto-complétion AD indisponible...",
        "Information",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    }
}

# === Fonction de détection de salle ===
function Get-SalleFromAD {
    if (-not $script:PrerequisOK) { return }

    $pc = $txtPC.Text.Trim()
    if ($pc.Length -lt 5) { return }

    try {
        $null = Import-Module ActiveDirectory -ErrorAction Stop
        $ADObj = Get-ADComputer $pc -Properties distinguishedName -ErrorAction Stop

        # DN exemple : CN=NOM_DU_POSTE,OU=SALLE,OU=Postes,DC=domaine,DC=local -> salle = SALLE
        $dn = $ADObj.distinguishedName
        $parts = $dn -split ","
        $salle = ($parts[1] -replace "^OU=", "")

        if ($txtDesc.Text -eq "" -or $txtDesc.Text -match '^[A-Za-z0-9\-\s]*$') {
            $txtDesc.Text = "$salle-"
        }
    }
    catch { }
}

# === Déclenchement de Get-SalleFromAD (anti-lag) ===

# Quand l’utilisateur valide avec Entrée
$null = $txtPC.Add_KeyDown({
    if ($_.KeyCode -eq "Enter") {
        Get-SalleFromAD
    }
    $null
})

# Quand il sélectionne via la liste ou quitte la TextBox
$null = $txtPC.Add_Leave({
    Get-SalleFromAD
    $null
})

# Label Desc
$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = "Description :"
$lblDesc.Location = "20,110"
$lblDesc.AutoSize = $true
$form.Controls.Add($lblDesc)

# Champ Desc (48 caractères maximum : limite Windows de la description d'un poste)
$txtDesc = New-Object System.Windows.Forms.TextBox
$txtDesc.Location = "130,107"
$txtDesc.Width = 180
$txtDesc.Font = $baseFont
$txtDesc.MaxLength = 48
$form.Controls.Add($txtDesc)
$txtDesc.Anchor = 'Top,Left,Right'

# Entrée dans la description = Appliquer
$null = $txtDesc.Add_KeyDown({
    if ($_.KeyCode -eq "Enter") {
        $_.SuppressKeyPress = $true
        if ($btnApply.Enabled) { $btnApply.PerformClick() }
    }
    $null
})

# Saut de ligne standard Windows (WinForms)
$nl = [Environment]::NewLine

# Traitement par lot en cours (CSV ou nouvelle tentative) et demande d'annulation
$script:IsCsvRunning = $false
$script:CancelRequested = $false

# Dernier CSV traité : sert à nommer le rapport et le fichier des échecs
$script:CsvPath = $null


############################################
# Creation bouton
############################################

# Tailles et positions des boutons
$btnWidth  = 130
$btnHeight = 30
$btnLeftX  = 20
$btnGap    = 10
$btnRightX = $btnLeftX + $btnWidth + $btnGap
$btnRetryX = $btnRightX + $btnWidth + $btnGap

# Bouton Vérifier le PC
$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text = "Vérifier le PC"
$btnTest.Location = "$btnLeftX,150"
$btnTest.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$form.Controls.Add($btnTest)

# Bouton Appliquer
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Appliquer"
$btnApply.Location = "$btnLeftX,188"
$btnApply.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$form.Controls.Add($btnApply)

# Bouton Aide CSV
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "Aide CSV"
$btnHelp.Location = "$btnRightX,150"
$btnHelp.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$form.Controls.Add($btnHelp)

# Bouton Traiter CSV
$btnCSV = New-Object System.Windows.Forms.Button
$btnCSV.Text = "Traiter CSV"
$btnCSV.Location = "$btnRightX,188"
$btnCSV.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$form.Controls.Add($btnCSV)

# Bouton Réessayer les échecs (actif dès que le suivi contient des postes en échec)
$btnRetry = New-Object System.Windows.Forms.Button
$btnRetry.Text = "Réessayer les échecs"
$btnRetry.Location = "$btnRetryX,188"
$btnRetry.Size = New-Object System.Drawing.Size($btnWidth,$btnHeight)
$btnRetry.Enabled = $false
$form.Controls.Add($btnRetry)

############################################
# Style boutons (flat / moderne)
############################################

function Set-ButtonStyle {
    param(
        [System.Windows.Forms.Button]$Button,
        [switch]$Primary
    )
    $Button.FlatStyle = 'Flat'
    $Button.Font = $baseFont
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Primary) {
        $Button.BackColor = $accentColor
        $Button.ForeColor = [System.Drawing.Color]::White
        $Button.FlatAppearance.BorderSize = 0
        $Button.FlatAppearance.MouseOverBackColor = $accentColorHover
        $Button.FlatAppearance.MouseDownBackColor = $accentColorHover
    }
    else {
        $Button.BackColor = [System.Drawing.Color]::White
        $Button.ForeColor = $textColor
        $Button.FlatAppearance.BorderSize = 1
        $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(210,210,210)
        $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(238,238,238)
        $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(225,225,225)
    }
}

Set-ButtonStyle -Button $btnTest
Set-ButtonStyle -Button $btnApply -Primary
Set-ButtonStyle -Button $btnHelp
Set-ButtonStyle -Button $btnCSV -Primary
Set-ButtonStyle -Button $btnRetry

############################################
# Zone de résultat rapide (test / appliquer)
############################################

$txtOut = New-Object System.Windows.Forms.TextBox
$txtOut.Location = "20,230"
$txtOut.Width = 280
$txtOut.Height = 55
$txtOut.Font = $baseFont
$txtOut.ReadOnly = $true
$txtOut.Anchor = 'Top,Left,Right'
$txtOut.Multiline = $true
$txtOut.ScrollBars = 'Vertical'
$txtOut.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($txtOut)

############################################
# Suivi en temps réel (traitement CSV)
############################################

$lblGrid = New-Object System.Windows.Forms.Label
$lblGrid.Text = "Suivi de la session (Ctrl+C : copier la sélection) :"
$lblGrid.Location = "20,295"
$lblGrid.AutoSize = $true
$lblGrid.Anchor = 'Top,Left'
$form.Controls.Add($lblGrid)

$gridResults = New-Object System.Windows.Forms.DataGridView
$gridResults.Location = "20,318"
$gridResults.Anchor = 'Top,Left,Right,Bottom'
$gridResults.ReadOnly = $true
$gridResults.AllowUserToAddRows = $false
$gridResults.AllowUserToDeleteRows = $false
$gridResults.AllowUserToResizeRows = $false
$gridResults.RowHeadersVisible = $false
$gridResults.SelectionMode = 'FullRowSelect'
$gridResults.MultiSelect = $true
$gridResults.ClipboardCopyMode = 'EnableAlwaysIncludeHeaderText'
$gridResults.BackgroundColor = [System.Drawing.Color]::White
$gridResults.BorderStyle = 'FixedSingle'
$gridResults.GridColor = [System.Drawing.Color]::FromArgb(230,230,230)
$gridResults.Font = $baseFont
$gridResults.ColumnHeadersHeightSizeMode = 'DisableResizing'
$gridResults.ColumnHeadersDefaultCellStyle.BackColor = $accentColor
$gridResults.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$gridResults.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI",9,[System.Drawing.FontStyle]::Bold)
$gridResults.EnableHeadersVisualStyles = $false
$gridResults.RowTemplate.Height = 22
$gridResults.AutoSizeColumnsMode = 'Fill'
$null = $gridResults.Columns.Add('colPC', 'PC')
$null = $gridResults.Columns.Add('colDesc', 'Description')
$null = $gridResults.Columns.Add('colEtat', 'État')
# Colonne État : en mode remplissage comme les autres (sinon le séparateur Description | État n'est plus
# déplaçable), mais jamais plus étroite que son libellé le plus long pour ne pas être tronquée
$gridResults.Columns['colEtat'].FillWeight = 60
$gridResults.Columns['colEtat'].MinimumWidth = [System.Windows.Forms.TextRenderer]::MeasureText("PING K.O · réveil envoyé", $baseFont).Width + 16
$form.Controls.Add($gridResults)

# Couleurs de statut (lignes du suivi)
$colorOkBack   = [System.Drawing.Color]::FromArgb(223,246,221)
$colorOkFore   = [System.Drawing.Color]::FromArgb(30,90,30)
$colorKoBack   = [System.Drawing.Color]::FromArgb(253,231,230)
$colorKoFore   = [System.Drawing.Color]::FromArgb(140,20,20)
$colorWolBack  = [System.Drawing.Color]::FromArgb(255,243,205)
$colorWolFore  = [System.Drawing.Color]::FromArgb(133,77,14)

# États affichés en vert ; « réveil envoyé » en orange ; les autres (PING K.O, ADMIN$ K.O, ERREUR,
# LIGNE INVALIDE, DESC. TROP LONGUE) en rouge
$etatsOK = @('OK', 'JOIGNABLE')
$etatReveil = 'PING K.O · réveil envoyé'

# Échecs qu'une nouvelle tentative peut résoudre (poste éteint, accès refusé, erreur passagère)
$etatsReessayables = @('PING K.O', $etatReveil, 'ADMIN$ K.O', 'ERREUR')

function Set-SuiviRowEtat {
    param($Row, [string]$Etat)

    $Row.Cells['colEtat'].Value = $Etat
    if ($etatsOK -contains $Etat) {
        $Row.DefaultCellStyle.BackColor = $colorOkBack
        $Row.DefaultCellStyle.ForeColor = $colorOkFore
    }
    elseif ($Etat -eq $etatReveil) {
        $Row.DefaultCellStyle.BackColor = $colorWolBack
        $Row.DefaultCellStyle.ForeColor = $colorWolFore
    }
    else {
        $Row.DefaultCellStyle.BackColor = $colorKoBack
        $Row.DefaultCellStyle.ForeColor = $colorKoFore
    }
}

# Fait défiler jusqu'à la ligne sans la sélectionner : le bleu de sélection masquerait sa couleur d'état
function Show-SuiviRow {
    param($Row)

    $gridResults.ClearSelection()
    $gridResults.FirstDisplayedScrollingRowIndex = $Row.Index
    [System.Windows.Forms.Application]::DoEvents()
}

# Ajoute une ligne au suivi. Action : 'csv' ou 'appliquer' (relançables en cas d'échec), 'verifier' (lecture seule)
function Add-SuiviRow {
    param([string]$PC, [string]$Desc, [string]$Etat, [string]$Action)

    $rowIndex = $gridResults.Rows.Add($PC, $Desc, $Etat)
    $row = $gridResults.Rows[$rowIndex]
    $row.Tag = @{ Action = $Action; PC = $PC; Desc = $Desc }
    Set-SuiviRowEtat $row $Etat
    Show-SuiviRow $row
    $row
}

# Lignes en échec que « Réessayer les échecs » peut relancer
function Get-LignesAReessayer {
    @($gridResults.Rows | Where-Object { $_.Tag -and $_.Tag.Action -ne 'verifier' -and $etatsReessayables -contains "$($_.Cells['colEtat'].Value)" })
}

function Update-BoutonReessayer {
    $btnRetry.Enabled = $script:PrerequisOK -and -not $script:IsCsvRunning -and (Get-LignesAReessayer).Count -gt 0
}

############################################
# Action Tooltips
############################################

# Tooltips
$toolTip.SetToolTip($txtPC,   "Nom du poste tel qu'il apparaît dans l'Active Directory")
$toolTip.SetToolTip($txtDesc, "Description à appliquer au poste (48 caractères maximum, limite Windows). Entrée = Appliquer")

$toolTip.SetToolTip($btnTest,  "Teste l'accès (Ping + ADMIN$) et lit la description actuelle")
$toolTip.SetToolTip($btnApply,"Applique la description dans le registre et l'AD")
$toolTip.SetToolTip($btnHelp, "Affiche l'aide sur le format CSV attendu")
$toolTip.SetToolTip($btnCSV,  "Traite un fichier CSV et suit la progression en temps réel (le fichier peut aussi être déposé sur la fenêtre)")
$toolTip.SetToolTip($btnRetry, "Relance les postes en échec du suivi ; les postes éteints dont la MAC est connue sont d'abord réveillés (Wake-on-LAN)")

############################################
# Fonction
############################################

#Fonction Désactiver/Activer l'ui pendant traitement
function Disable-UI {
    $btnTest.Enabled  = $false
    $btnApply.Enabled = $false
    $btnHelp.Enabled  = $false
    $btnRetry.Enabled = $false
    # $btnCSV reste actif : il devient « Annuler »
    Set-LiensEnTeteActifs $false
}

function Enable-UI {
    $btnTest.Enabled  = $true
    $btnApply.Enabled = $true
    $btnHelp.Enabled  = $true
    $btnCSV.Enabled   = $true
    Set-LiensEnTeteActifs $true
    Update-BoutonReessayer
}
#Fonction StatusBar
function Set-Status {
    param (
        [string]$Text
    )

    $statusLabel.Text = $Text
    $statusBar.Refresh()
}
#Fonction CsvButtonMode/annuler
function Set-CsvButtonMode {
    param([bool]$Running)

    if ($Running) {
        $btnCSV.Text = "Annuler"
    } else {
        $btnCSV.Text = "Traiter CSV"
    }
}

############################################
# Accès aux postes et traitement par lot
############################################

# Ping puis partage ADMIN$ : $null si le poste est accessible, sinon l'état d'échec
function Test-AccesPoste {
    param([string]$PC)

    if (!(Test-Connection -ComputerName $PC -Count 1 -Quiet)) { return "PING K.O" }
    if (!(Test-Path "\\$PC\ADMIN$")) { return "ADMIN$ K.O" }
    $null
}

# Écrit la description dans le registre du poste (relue pour contrôle) puis dans l'AD.
# Renvoie l'état (OK, PING K.O, ADMIN$ K.O, ERREUR) et, pour ERREUR, l'étape en cause et le message
function Set-DescriptionPoste {
    param([string]$PC, [string]$Desc)

    $acces = Test-AccesPoste $PC
    if ($acces) { return [PSCustomObject]@{ Etat = $acces; Detail = "" } }

    $etape = "Registre"
    try {
        $r = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $PC)
        $k = $r.OpenSubKey('SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters', $true)
        $k.SetValue('srvcomment', $Desc, 'String')
        $relu = $k.GetValue('srvcomment')
        $k.Close()
        if ("$relu" -ne $Desc) { throw "valeur relue « $relu » différente de la valeur écrite" }

        $etape = "AD"
        $null = Import-Module ActiveDirectory -ErrorAction Stop
        Set-ADComputer -Identity $PC -Description $Desc

        [PSCustomObject]@{ Etat = "OK"; Detail = "" }
    }
    catch {
        $detail = "$etape : $($_.Exception.Message)"
        if ($etape -eq "AD") { $detail += " (le registre du poste, lui, a été mis à jour)" }
        [PSCustomObject]@{ Etat = "ERREUR"; Detail = $detail }
    }
}

# Traite une liste de postes avec progression et annulation ; utilisé par « Traiter CSV » et « Réessayer les échecs ».
# Chaque élément : PC, Desc, Action et Row (ligne du suivi à mettre à jour, ou $null pour en ajouter une).
# Un poste éteint dont la MAC est connue est réveillé (Wake-on-LAN) ; les postes réveillés sont ensuite
# attendus puis traités dès qu'ils répondent.
function Invoke-LotPostes {
    param([array]$Lignes, [string]$Libelle)

    $script:IsCsvRunning = $true
    $script:CancelRequested = $false
    Set-CsvButtonMode $true
    Disable-UI
    $progressBar.Visible = $true
    $progressBar.Value = 0

    $index = 0
    $total = $Lignes.Count
    $traitees = @()
    $reveillees = @()

    try {
        if ($script:WolDisponible) {
            Set-Status "$Libelle : lecture des adresses MAC (DHCP, AD)..."
            Update-CarteMac
        }

        foreach ($ligne in $Lignes) {

            if ($script:CancelRequested) {
                Set-Status "$Libelle : annulé ($index / $total)"
                break
            }

            if ($ligne.PC -eq "" -or $ligne.Desc -eq "") {
                # PC ou description manquant : ligne signalée, rien n'est modifié
                $etat = "LIGNE INVALIDE"
            }
            elseif ($ligne.Desc.Length -gt 48) {
                # Windows limite la description d'un poste à 48 caractères
                $etat = "DESC. TROP LONGUE"
            }
            else {
                $etat = (Set-DescriptionPoste -PC $ligne.PC -Desc $ligne.Desc).Etat
                if ($etat -eq "PING K.O" -and (Send-Reveil -PC $ligne.PC)) {
                    $etat = $etatReveil
                    $reveillees += $ligne
                }
            }

            if ($ligne.Row) {
                Set-SuiviRowEtat $ligne.Row $etat
                Show-SuiviRow $ligne.Row
            }
            else {
                $ligne.Row = Add-SuiviRow -PC $ligne.PC -Desc $ligne.Desc -Etat $etat -Action $ligne.Action
            }
            $traitees += $ligne

            $index++
            $progressBar.Value = [Math]::Min(100, [int](($index / $total) * 100))
            Set-Status "$Libelle... ($index / $total)"

            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($reveillees.Count -gt 0 -and -not $script:CancelRequested) {
            Wait-PostesReveilles -Lignes $reveillees -Libelle $Libelle
        }

        if (-not $script:CancelRequested) {
            Set-Status "$Libelle : terminé"
        }
    }
    finally {
        $progressBar.Value = 0
        $progressBar.Visible = $false

        $script:IsCsvRunning = $false
        $script:CancelRequested = $false
        Set-CsvButtonMode $false
        Enable-UI
    }

    # Bilan d'après l'état final des lignes (les postes réveillés ont pu changer d'état pendant l'attente)
    $nbOK = @($traitees | Where-Object { $etatsOK -contains "$($_.Row.Cells['colEtat'].Value)" }).Count
    [PSCustomObject]@{ OK = $nbOK; KO = ($traitees.Count - $nbOK); Traites = $traitees.Count; Total = $total }
}

# Propose le rapport CSV du suivi ; s'il reste des échecs relançables, les exporte aussi
# dans un CSV au format d'entrée (PC;Description), prêt à être repassé dans « Traiter CSV »
function Export-RapportSiDemande {
    if (-not $script:CsvPath) { return }

    $reponse = [System.Windows.Forms.MessageBox]::Show(
        $form,
        "Voulez-vous générer le rapport CSV du traitement ?",
        "Rapport",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($reponse -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $date = Get-Date -Format "yyyy-MM-dd_HH-mm"

        $rep = $script:CsvPath -replace "\.csv$", "_RAPPORT_$date.csv"
        @($gridResults.Rows | ForEach-Object {
            [PSCustomObject]@{
                PC          = "$($_.Cells['colPC'].Value)"
                Description = "$($_.Cells['colDesc'].Value)"
                Etat        = "$($_.Cells['colEtat'].Value)"
            }
        }) | Export-Csv -Path $rep -Delimiter ";" -NoTypeInformation -Encoding UTF8
        $txtOut.Text += $nl + "Rapport exporté : $rep"

        $echecs = Get-LignesAReessayer
        if ($echecs.Count -gt 0) {
            $fic = $script:CsvPath -replace "\.csv$", "_ECHECS_$date.csv"
            @($echecs | ForEach-Object { [PSCustomObject]@{ PC = $_.Tag.PC; Description = $_.Tag.Desc } }) |
                Export-Csv -Path $fic -Delimiter ";" -NoTypeInformation -Encoding UTF8
            $txtOut.Text += $nl + "Postes en échec, à repasser dans « Traiter CSV » : $fic"
        }
    }
    catch {
        $txtOut.Text += $nl + "Export impossible : $($_.Exception.Message)"
    }
}

# Bilan d'un lot dans la zone de résultat, puis proposition du rapport
function Show-BilanLot {
    param($Bilan, [string]$Libelle)

    $texte = "$Libelle : OK = $($Bilan.OK) | Échecs = $($Bilan.KO)"
    if ($Bilan.Traites -lt $Bilan.Total) { $texte += " | Non traités = $($Bilan.Total - $Bilan.Traites)" }

    $nbEchecs = (Get-LignesAReessayer).Count
    if ($nbEchecs -gt 0) {
        $texte += $nl + $(if ($script:WolDisponible) { "$nbEchecs poste(s) en échec : « Réessayer les échecs » les réveille (MAC connue) puis les relance." }
                          else { "$nbEchecs poste(s) en échec : « Réessayer les échecs » les relance (par exemple une fois les postes allumés)." })
    }

    $txtOut.Text = $texte
    Update-BoutonReessayer
    Export-RapportSiDemande
}

# Lance le traitement d'un fichier CSV (bouton « Traiter CSV » ou fichier déposé sur la fenêtre)
function Start-TraitementCsv {
    param([string]$Chemin)

    if ($script:IsCsvRunning -or -not $btnCSV.Enabled) { return }

    # Confirmation avant traitement
    $nomFichier = [System.IO.Path]::GetFileName($Chemin)
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        $form,
        "Le fichier ""$nomFichier"" va être utilisé pour modifier les postes listés.${nl}${nl}Êtes-vous sûr de vouloir continuer ?",
        "Confirmation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        # @() : sous PowerShell 5.1, un CSV d'une seule ligne ne renvoie pas de tableau (pas de .Count)
        $data = @(Import-Csv -Path $Chemin -Delimiter ";")

        # En-tête obligatoire : colonnes PC et Description
        if ($data.Count -gt 0) {
            $colonnes = @($data[0].PSObject.Properties.Name)
            if ($colonnes -notcontains 'PC' -or $colonnes -notcontains 'Description') {
                Set-Status "Erreur CSV"
                $txtOut.Text = "Erreur CSV : fichier non conforme (en-tête PC;Description attendu)."
                return
            }
        }

        # Lignes entièrement vides (ex. « ; » ajoutés par Excel) : ignorées
        $data = @($data | Where-Object { "$($_.PC)".Trim() -ne "" -or "$($_.Description)".Trim() -ne "" })

        if ($data.Count -eq 0) {
            $txtOut.Text = "Aucun poste à traiter dans ce fichier."
            return
        }

        $script:CsvPath = $Chemin
        $gridResults.Rows.Clear()
        Update-BoutonReessayer
        $txtOut.Text = "Traitement en cours — suivi ci-dessous."
        Set-Status "Traitement du CSV..."

        $lignes = @($data | ForEach-Object {
            [PSCustomObject]@{ Row = $null; PC = "$($_.PC)".Trim(); Desc = "$($_.Description)".Trim(); Action = 'csv' }
        })
        $bilan = Invoke-LotPostes -Lignes $lignes -Libelle "Traitement du CSV"
        Show-BilanLot -Bilan $bilan -Libelle "Résumé"
    }
    catch {
        Set-Status "Erreur CSV"
        $txtOut.Text = "Erreur CSV : $($_.Exception.Message)"
    }
    finally {
        Set-Status "Prêt"
    }
}

############################################
# Action bouton
############################################

# Action Aide CSV
$null = $btnHelp.Add_Click({
    [void][System.Windows.Forms.MessageBox]::Show(
"FORMAT CSV OBLIGATOIRE :

PC;Description
NOM_DU_POSTE_1;Description du poste 1
NOM_DU_POSTE_2;Description du poste 2

RÈGLES :
- Séparateur : point-virgule (;)
- Première ligne obligatoire
- Un PC par ligne
- Description : 48 caractères maximum (limite Windows)
- Ligne sans PC ou sans description : signalée « LIGNE INVALIDE », non appliquée

ASTUCES :
- Le fichier peut aussi être déposé directement sur la fenêtre
- Avec le rapport, les postes en échec sont exportés dans un fichier _ECHECS_, prêt à être repassé ici",
"Aide – Format CSV",
[System.Windows.Forms.MessageBoxButtons]::OK,
[System.Windows.Forms.MessageBoxIcon]::Information
    )
})

# Action Vérifier le PC : accès (ping + ADMIN$), description actuelle et système du poste
$null = $btnTest.Add_Click({
    $pc = $txtPC.Text.Trim()

    if ($pc -eq "") {
        $txtOut.Text = "Aucun PC spécifié."
        return
    }

    try {
        Set-Status "Vérification de $pc..."
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        $acces = Test-AccesPoste $pc
        if ($acces) {
            $message = "ADMIN$ K.O : pas d'accès administrateur sur $pc."
            if ($acces -eq "PING K.O") {
                $message = "Ping K.O : $pc est hors ligne."
                if ($script:WolDisponible) {
                    $info = Get-InfoReveil $pc
                    if (-not $info) { Update-CarteMac; $info = Get-InfoReveil $pc }
                    if ($info -and (Send-Reveil -PC $pc)) {
                        $acces = $etatReveil
                        $message += " Réveil envoyé (MAC $($info.Mac)) : revérifiez dans une minute."
                    }
                    else { $message += " MAC inconnue (aucun bail DHCP ni MAC mémorisée) : réveil impossible." }
                }
            }
            $null = Add-SuiviRow -PC $pc -Desc "" -Etat $acces -Action 'verifier'
            $txtOut.Text = $message
            return
        }

        $r = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $pc)
        $k = $r.OpenSubKey('SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters', $false)
        $val = $k.GetValue('srvcomment')
        $k.Close()

        $kOS = $r.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion', $false)
        $product = $kOS.GetValue('ProductName')
        $version = $kOS.GetValue('DisplayVersion')
        if (-not $version) { $version = $kOS.GetValue('ReleaseId') }
        $kOS.Close()

        $info = Get-InfoReveil $pc
        $ligneWol = if (-not $script:WolDisponible) { "Réveil (WoL) : indisponible ($($script:WolMotif))" }
                    elseif ($info -and $info.Diffusion) { "Réveil (WoL) : MAC $($info.Mac), diffusion $($info.Diffusion)" }
                    elseif ($info) { "Réveil (WoL) : MAC $($info.Mac) (mémorisée dans l'AD)" }
                    else { "Réveil (WoL) : MAC inconnue pour l'instant" }

        $null = Add-SuiviRow -PC $pc -Desc "$val" -Etat "JOIGNABLE" -Action 'verifier'
        $txtOut.Text =
        "OK : $pc est joignable." + $nl +
        "Description actuelle : $val" + $nl +
        "OS : $product $version" + $nl +
        $ligneWol
    }
    catch {
        $null = Add-SuiviRow -PC $pc -Desc "" -Etat "ERREUR" -Action 'verifier'
        $txtOut.Text = "Erreur : $($_.Exception.Message)"
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        Set-Status "Prêt"
    }
})
# Action Appliquer : mêmes contrôles que le traitement CSV (ping + ADMIN$), puis registre et AD
$null = $btnApply.Add_Click({
    $pc = $txtPC.Text.Trim()
    $desc = $txtDesc.Text.Trim()

    if ($pc -eq "" -or $desc -eq "") {
        $txtOut.Text = "Champs incomplets."
        return
    }

    try {
        Set-Status "Application sur $pc..."
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        $resultat = Set-DescriptionPoste -PC $pc -Desc $desc
        $null = Add-SuiviRow -PC $pc -Desc $desc -Etat $resultat.Etat -Action 'appliquer'

        $txtOut.Text = switch ($resultat.Etat) {
            "OK"         { "Description appliquée sur $pc : registre et AD mis à jour." }
            "PING K.O"   { "Ping K.O : $pc est hors ligne. Rien n'a été modifié." }
            "ADMIN$ K.O" { "ADMIN$ K.O : pas d'accès administrateur sur $pc. Rien n'a été modifié." }
            default      { "Erreur sur $pc — $($resultat.Detail)" }
        }
        Update-BoutonReessayer
    }
    catch {
        $txtOut.Text = "Erreur : $($_.Exception.Message)"
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        Set-Status "Prêt"
    }
})
# Action Traiter CSV (un 2e clic pendant un lot demande l'annulation)
$null = $btnCSV.Add_Click({

    if ($script:IsCsvRunning) {
        $script:CancelRequested = $true
        Set-Status "Annulation demandée..."
        return
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Fichier CSV (*.csv)|*.csv"
    $dialog.Title = "Sélectionner un fichier CSV"
    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

    Start-TraitementCsv -Chemin $dialog.FileName
})

# Action Réessayer les échecs : relance, sur place dans le suivi, les postes en échec
$null = $btnRetry.Add_Click({
    if ($script:IsCsvRunning) { return }

    $lignesEchec = Get-LignesAReessayer
    if ($lignesEchec.Count -eq 0) {
        Update-BoutonReessayer
        return
    }

    try {
        $txtOut.Text = "Nouvelle tentative sur $($lignesEchec.Count) poste(s) en échec..."
        Set-Status "Nouvelle tentative..."

        $lignes = @($lignesEchec | ForEach-Object {
            [PSCustomObject]@{ Row = $_; PC = $_.Tag.PC; Desc = $_.Tag.Desc; Action = $_.Tag.Action }
        })
        $bilan = Invoke-LotPostes -Lignes $lignes -Libelle "Nouvelle tentative"
        Show-BilanLot -Bilan $bilan -Libelle "Nouvelle tentative"
    }
    catch {
        Set-Status "Erreur"
        $txtOut.Text = "Erreur : $($_.Exception.Message)"
    }
    finally {
        Set-Status "Prêt"
    }
})

############################################
# Glisser-déposer d'un fichier CSV sur la fenêtre
############################################

# Chemin du CSV déposé, s'il s'agit d'un seul fichier .csv
function Get-CsvDepose {
    param($Donnees)

    if (-not $Donnees.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { return $null }
    $fichiers = @($Donnees.GetData([System.Windows.Forms.DataFormats]::FileDrop))
    if ($fichiers.Count -ne 1 -or [System.IO.Path]::GetExtension($fichiers[0]) -ne '.csv') { return $null }
    $fichiers[0]
}

# Le traitement démarre juste après la fin du dépôt : un dialogue ouvert pendant le dépôt bloquerait l'Explorateur
$script:CsvDepose = $null
$timerDepot = New-Object System.Windows.Forms.Timer
$timerDepot.Interval = 100
$null = $timerDepot.Add_Tick({
    $timerDepot.Stop()
    $chemin = $script:CsvDepose
    $script:CsvDepose = $null
    if ($chemin) { Start-TraitementCsv -Chemin $chemin }
})

$surDragEnter = {
    $ok = $btnCSV.Enabled -and -not $script:IsCsvRunning -and (Get-CsvDepose $_.Data)
    $_.Effect = if ($ok) { [System.Windows.Forms.DragDropEffects]::Copy } else { [System.Windows.Forms.DragDropEffects]::None }
}
$surDragDrop = {
    $chemin = Get-CsvDepose $_.Data
    if ($chemin -and $btnCSV.Enabled -and -not $script:IsCsvRunning) {
        $script:CsvDepose = $chemin
        $timerDepot.Start()
    }
}

foreach ($cible in @($form, $pnlHeader, $txtOut, $gridResults)) {
    $cible.AllowDrop = $true
    $null = $cible.Add_DragEnter($surDragEnter)
    $null = $cible.Add_DragDrop($surDragDrop)
}

############################################
# Réveil des postes (Wake-on-LAN)
############################################
# Le magic packet vise la MAC du poste et part en diffusion dirigée sur le sous-réseau de l'étendue DHCP,
# jamais vers l'IP du poste (elle change). Les MAC viennent des baux et réservations DHCP du serveur, et sont
# mémorisées dans l'AD (attribut networkAddress de l'objet ordinateur) pour survivre à l'expiration des baux.

$script:WolDisponible = $false
$script:WolMotif      = ""
$script:WolAttenteMax = 120        # secondes d'attente maximum des postes réveillés
$script:ServeurDhcp   = $null      # $null = serveur DHCP local (l'outil tourne sur le DC), sinon nom du serveur
$script:Etendues      = @()        # étendues DHCP : ScopeId, Masque, Diffusion
$script:MacDhcp       = @{}        # NOM DE POSTE -> @{ Mac ; Diffusion } (baux et réservations en cours)
$script:MacAD         = @{}        # NOM DE POSTE -> MAC mémorisée dans l'AD

# Adresse de diffusion d'un sous-réseau (adresse OU inverse du masque)
function Get-Diffusion {
    param([string]$Adresse, [string]$Masque)

    $a = [System.Net.IPAddress]::Parse($Adresse).GetAddressBytes()
    $m = [System.Net.IPAddress]::Parse($Masque).GetAddressBytes()
    $b = [byte[]](0..3 | ForEach-Object { [byte]($a[$_] -bor ((-bnot $m[$_]) -band 0xFF)) })
    (New-Object System.Net.IPAddress(,$b)).ToString()
}

# Paramètres communs aux cmdlets DHCP (serveur local ou distant)
function Get-ParamsDhcp {
    if ($script:ServeurDhcp) { @{ ComputerName = $script:ServeurDhcp } } else { @{} }
}

# Détecte le DHCP : module présent et étendues lisibles, en local puis sur le serveur d'ouverture de session
function Initialize-Wol {
    if (-not $script:PrerequisOK) { $script:WolMotif = "prérequis non remplis"; return }
    if (-not (Get-Module -ListAvailable -Name DhcpServer)) { $script:WolMotif = "module PowerShell DhcpServer absent (rôle DHCP ou outils RSAT DHCP)"; return }

    try { $null = Import-Module DhcpServer -ErrorAction Stop }
    catch { $script:WolMotif = "module DhcpServer inutilisable : $($_.Exception.Message)"; return }

    $serveurs = @($null)
    if ($env:LOGONSERVER) { $serveurs += ($env:LOGONSERVER -replace '^\\\\', '') }
    foreach ($serveur in $serveurs) {
        try {
            $script:ServeurDhcp = $serveur
            $params = Get-ParamsDhcp
            $script:Etendues = @(Get-DhcpServerv4Scope @params -ErrorAction Stop | ForEach-Object {
                $reseau = $_.ScopeId.IPAddressToString
                $masque = $_.SubnetMask.IPAddressToString
                [PSCustomObject]@{ ScopeId = $reseau; Masque = $masque; Diffusion = (Get-Diffusion $reseau $masque) }
            })
            if ($script:Etendues.Count -gt 0) { $script:WolDisponible = $true; $script:WolMotif = ""; return }
            $script:WolMotif = "aucune étendue DHCP"
        }
        catch { $script:WolMotif = "DHCP inaccessible : $($_.Exception.Message)" }
    }
    $script:ServeurDhcp = $null
}

# Relit les baux et réservations DHCP, puis mémorise dans l'AD les MAC nouvelles ou changées
function Update-CarteMac {
    if (-not $script:WolDisponible) { return }

    $carte = @{}
    $params = Get-ParamsDhcp
    foreach ($e in $script:Etendues) {
        $entrees = @()
        try { $entrees += @(Get-DhcpServerv4Lease @params -ScopeId $e.ScopeId -ErrorAction Stop) } catch { }
        try { $entrees += @(Get-DhcpServerv4Reservation @params -ScopeId $e.ScopeId -ErrorAction Stop) } catch { }
        foreach ($b in $entrees) {
            # HostName pour un bail, Name pour une réservation ; nom court, en majuscules
            $nom = ("$($b.HostName)$($b.Name)" -split '\.')[0].ToUpper()
            if ($nom -and "$($b.ClientId)" -match '^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$') {
                $carte[$nom] = @{ Mac = "$($b.ClientId)".ToLower(); Diffusion = $e.Diffusion }
            }
        }
    }
    $script:MacDhcp = $carte

    try {
        $memoire = @{}
        foreach ($c in @(Get-ADComputer -Filter * -Properties networkAddress -ErrorAction Stop)) {
            $nom = $c.Name.ToUpper()
            $mac = @($c.networkAddress | Where-Object { "$_" -match '^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$' })[0]
            if ($carte.ContainsKey($nom) -and $carte[$nom].Mac -ne $mac) {
                try {
                    Set-ADComputer -Identity $c -Replace @{ networkAddress = $carte[$nom].Mac } -ErrorAction Stop
                    $mac = $carte[$nom].Mac
                }
                catch { }
            }
            if ($mac) { $memoire[$nom] = "$mac".ToLower() }
        }
        $script:MacAD = $memoire
    }
    catch { }
}

# MAC et diffusion connues pour un poste : DHCP d'abord, puis mémoire AD (diffusion : toutes les étendues)
function Get-InfoReveil {
    param([string]$PC)

    $nom = $PC.ToUpper()
    if ($script:MacDhcp.ContainsKey($nom)) { return $script:MacDhcp[$nom] }
    if ($script:MacAD.ContainsKey($nom)) { return @{ Mac = $script:MacAD[$nom]; Diffusion = $null } }
    $null
}

# Magic packet : 6 octets FF puis 16 fois la MAC, en UDP sur les ports 9 et 7
function Send-MagicPacket {
    param([string]$Mac, [string]$Diffusion)

    $octets = @($Mac -split '[-:]' | ForEach-Object { [Convert]::ToByte($_, 16) })
    if ($octets.Count -ne 6) { throw "MAC invalide : $Mac" }
    $paquet = New-Object byte[] 102
    for ($i = 0; $i -lt 6; $i++) { $paquet[$i] = 0xFF }
    for ($i = 0; $i -lt 16; $i++) { for ($j = 0; $j -lt 6; $j++) { $paquet[6 + $i * 6 + $j] = $octets[$j] } }
    foreach ($port in 9, 7) {
        $udp = New-Object System.Net.Sockets.UdpClient
        try {
            $udp.EnableBroadcast = $true
            [void]$udp.Send($paquet, $paquet.Length, $Diffusion, $port)
        }
        finally { $udp.Close() }
    }
}

# Réveille un poste si sa MAC est connue ; $true si un paquet est parti
function Send-Reveil {
    param([string]$PC)

    if (-not $script:WolDisponible) { return $false }
    $info = Get-InfoReveil $PC
    if (-not $info) { return $false }
    $cibles = if ($info.Diffusion) { @($info.Diffusion) } else { @($script:Etendues | ForEach-Object { $_.Diffusion }) }
    $envoye = $false
    foreach ($diffusion in $cibles) {
        try { Send-MagicPacket -Mac $info.Mac -Diffusion $diffusion; $envoye = $true } catch { }
    }
    $envoye
}

# Ping rapide (1 s) pour surveiller le retour des postes réveillés
function Test-PingRapide {
    param([string]$PC)

    try { (New-Object System.Net.NetworkInformation.Ping).Send($PC, 1000).Status -eq 'Success' } catch { $false }
}

# Attend les postes réveillés (annulable) et traite chacun dès qu'il répond ; au bout du délai,
# les postes toujours injoignables reprennent leur état réel (relançables avec « Réessayer les échecs »).
# Lignes : éléments du lot (PC, Desc, Row) dont l'état est « réveil envoyé »
function Wait-PostesReveilles {
    param([array]$Lignes, [string]$Libelle)

    $restantes = New-Object System.Collections.ArrayList
    foreach ($l in $Lignes) { [void]$restantes.Add($l) }
    $derniers = @{}
    $limite = $script:WolAttenteMax
    $chrono = [System.Diagnostics.Stopwatch]::StartNew()

    while ($restantes.Count -gt 0 -and $chrono.Elapsed.TotalSeconds -lt $limite -and -not $script:CancelRequested) {
        Set-Status ("$Libelle : attente des postes réveillés ({0} restant(s), {1} s)..." -f $restantes.Count, [int]($limite - $chrono.Elapsed.TotalSeconds))

        # 5 s de pause en gardant l'interface réactive (bouton Annuler)
        $fin = [DateTime]::Now.AddSeconds(5)
        while ([DateTime]::Now -lt $fin -and -not $script:CancelRequested) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }

        foreach ($ligne in @($restantes)) {
            if ($script:CancelRequested) { break }
            if (-not (Test-PingRapide $ligne.PC)) { continue }
            $acces = Test-AccesPoste $ligne.PC
            if ($acces) { $derniers[$ligne.PC] = $acces; continue }      # démarré, mais ADMIN$ pas encore prêt
            $etat = (Set-DescriptionPoste -PC $ligne.PC -Desc $ligne.Desc).Etat
            Set-SuiviRowEtat $ligne.Row $etat
            Show-SuiviRow $ligne.Row
            $restantes.Remove($ligne)
        }
    }

    foreach ($ligne in @($restantes)) {
        $etat = if ($derniers.ContainsKey($ligne.PC)) { $derniers[$ligne.PC] } else { "PING K.O" }
        Set-SuiviRowEtat $ligne.Row $etat
    }
}

############################################
# Rappel compte / domaine + blocage si prérequis non remplis
############################################

Initialize-Wol

$etatDomaine = if (-not $prerequis.Domaine) { "NON" }
               elseif ($prerequis.EstDC) { "OK ($($prerequis.NomDomaine), contrôleur de domaine)" }
               else { "OK ($($prerequis.NomDomaine))" }
$etatAdmin   = if ($prerequis.Admin) { "OK" } else { "NON" }
$etatModule  = if ($prerequis.ModuleAD) { "OK" } else { "NON" }
$etatWol     = if ($script:WolDisponible) {
                   $source = if ($script:ServeurDhcp) { "DHCP de $($script:ServeurDhcp)" } else { "DHCP local" }
                   "disponible ($source, diffusion " + (@($script:Etendues | ForEach-Object { $_.Diffusion }) -join ', ') + ")"
               }
               else { "indisponible ($($script:WolMotif))" }

$detailPrerequis =
    "Compte utilisé : $($prerequis.Compte)" + $nl + $nl +
    "Poste membre du domaine : $etatDomaine" + $nl +
    "Compte administrateur du domaine : $etatAdmin" + $nl +
    "Module ActiveDirectory (RSAT) : $etatModule" + $nl +
    "Réveil des postes (Wake-on-LAN) : $etatWol"

$lblSession.Text = if (-not $prerequis.Domaine) { "$($prerequis.Compte) · hors domaine" }
                   elseif ($prerequis.EstDC) { "$($prerequis.Compte) · $($prerequis.NomDomaine) (DC)" }
                   else { "$($prerequis.Compte) · $($prerequis.NomDomaine)" }
$lblSession.ToolTipText = $detailPrerequis

if (-not $script:PrerequisOK) {
    $btnTest.Enabled  = $false
    $btnApply.Enabled = $false
    $btnCSV.Enabled   = $false
    $btnRetry.Enabled = $false
    $lblSession.ForeColor = $colorKoFore

    $script:MessagePrerequis =
        "Cet outil doit être lancé sur le contrôleur de domaine, ou sur un poste membre du domaine, avec un compte administrateur du domaine." + $nl + $nl +
        $detailPrerequis + $nl + $nl +
        "Les fonctions « Vérifier le PC », « Appliquer » et « Traiter CSV » sont désactivées."

    $txtOut.Text = "Fonctions désactivées : prérequis non remplis." + $nl +
                   "À lancer sur le DC ou un poste du domaine, avec un compte admin du domaine."
    Set-Status "Prérequis non remplis — fonctions désactivées"
}

############################################
# Mise à jour automatique (releases GitHub)
############################################

# Dépôt public d'où viennent les mises à jour : cette adresse est inscrite dans chaque exe installé
$depotMaj = 'vzeol/computer-description-tool'

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# "v1.3" ou "1.3.0.0" -> [version] 1.3.0.0 (4 composantes, pour comparer le tag et la version de l'exe)
function ConvertTo-Version {
    param([string]$Texte)
    $parties = @(($Texte.Trim() -replace '^[vV]', '') -split '\.' | Where-Object { $_ -ne '' })
    while ($parties.Count -lt 4) { $parties += '0' }
    [version]($parties[0..3] -join '.')
}

# 1.3.0.0 -> "1.3" ; 1.2.99.0 -> "1.2.99"
function Format-Version {
    param([version]$Version)
    if ($Version.Build -gt 0) { "$($Version.Major).$($Version.Minor).$($Version.Build)" }
    else { "$($Version.Major).$($Version.Minor)" }
}

# Exe en cours d'exécution et sa version (celle passée à ps2exe -version).
# $null si l'outil est lancé en .ps1 (powershell.exe) : pas de mise à jour dans ce cas.
function Get-ExeActuel {
    try {
        $chemin = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([System.IO.Path]::GetFileNameWithoutExtension($chemin) -in 'powershell', 'powershell_ise', 'pwsh') { return $null }
        $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($chemin).FileVersion
        [PSCustomObject]@{ Chemin = $chemin; Version = ConvertTo-Version $version }
    }
    catch { $null }
}

# Dernière release publiée (ni brouillon ni pré-version).
# $null si pas d'accès à GitHub, pas de release, pas d'exe ou pas d'empreinte SHA256.
function Get-DerniereRelease {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$depotMaj/releases/latest" -TimeoutSec 5 -UseBasicParsing
        $asset = @($release.assets | Where-Object { $_.name -like '*.exe' })[0]
        if (-not $asset) { return $null }
        if ($asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { return $null }

        [PSCustomObject]@{
            Version = ConvertTo-Version $release.tag_name
            Tag     = $release.tag_name
            Notes   = [string]$release.body
            Url     = $asset.browser_download_url
            Sha256  = $Matches[1]
            Page    = $release.html_url
        }
    }
    catch { $null }
}

# Supprime les restes d'une mise à jour précédente (.old = ancienne version, .new = téléchargement interrompu).
# Juste après une mise à jour, l'ancienne version peut mettre un instant à se fermer : on réessaie un peu.
function Remove-RestesMiseAJour {
    param($Exe)
    foreach ($reste in "$($Exe.Chemin).old", "$($Exe.Chemin).new") {
        for ($i = 0; $i -lt 10 -and [System.IO.File]::Exists($reste); $i++) {
            try { [System.IO.File]::Delete($reste) } catch { Start-Sleep -Milliseconds 300 }
        }
    }
}

# Télécharge la release, vérifie son SHA256, remplace l'exe en cours et lance la nouvelle version.
# Windows interdit de supprimer un exe en cours d'exécution mais autorise à le renommer :
# l'exe actuel devient .old (supprimé au lancement suivant) et le nouveau prend sa place.
function Install-MiseAJour {
    param($Exe, $Release)

    $nouveau = "$($Exe.Chemin).new"
    $ancien  = "$($Exe.Chemin).old"

    $client = New-Object System.Net.WebClient
    try { $client.DownloadFile($Release.Url, $nouveau) } finally { $client.Dispose() }

    if ((Get-FileHash -LiteralPath $nouveau -Algorithm SHA256).Hash -ne $Release.Sha256) {
        [System.IO.File]::Delete($nouveau)
        throw "l'empreinte SHA256 du fichier téléchargé ne correspond pas à celle de la release."
    }

    if ([System.IO.File]::Exists($ancien)) { [System.IO.File]::Delete($ancien) }
    [System.IO.File]::Move($Exe.Chemin, $ancien)
    try {
        [System.IO.File]::Move($nouveau, $Exe.Chemin)
    }
    catch {
        # Remise en place de la version actuelle
        [System.IO.File]::Move($ancien, $Exe.Chemin)
        throw
    }

    $null = [System.Diagnostics.Process]::Start($Exe.Chemin)
}

# Au lancement : propose la mise à jour si une version plus récente est publiée.
# Renvoie $true si la nouvelle version a été lancée (l'outil actuel doit alors se fermer).
function Invoke-VerifMiseAJour {
    $exe = $script:ExeActuel
    if (-not $exe) { return $false }

    Remove-RestesMiseAJour -Exe $exe

    $statutAvant = $statusLabel.Text
    Set-Status "Recherche de mises à jour..."
    $release = Get-DerniereRelease
    Set-Status $statutAvant

    if (-not $release -or $release.Version -le $exe.Version) { return $false }

    $notes = ($release.Notes -replace '(?m)^#+\s*', '').Trim()
    if ($notes.Length -gt 800) { $notes = $notes.Substring(0, 800) + '…' }

    $reponse = [System.Windows.Forms.MessageBox]::Show(
        $form,
        "Une nouvelle version est disponible : $($release.Tag) (version actuelle : $(Format-Version $exe.Version)).${nl}${nl}$notes${nl}${nl}Mettre à jour maintenant ? L'outil redémarrera sur la nouvelle version.",
        "Mise à jour disponible",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($reponse -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    try {
        Set-Status "Téléchargement de la mise à jour..."
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        Install-MiseAJour -Exe $exe -Release $release
        return $true
    }
    catch {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        Set-Status $statutAvant
        [void][System.Windows.Forms.MessageBox]::Show(
            $form,
            "La mise à jour a échoué : $($_.Exception.Message)${nl}${nl}L'outil continue avec la version actuelle. La nouvelle version peut être téléchargée ici :${nl}$($release.Page)",
            "Mise à jour",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return $false
    }
}

# Version affichée dans le titre de la fenêtre
$script:ExeActuel = Get-ExeActuel
if ($script:ExeActuel) { $form.Text += " $(Format-Version $script:ExeActuel.Version)" }

############################################
# Icône, lien GitHub et « À propos »
############################################

$urlDepot = "https://github.com/$depotMaj"

# Icône de l'exe dans la barre de titre et la barre des tâches (absente si l'outil est lancé en .ps1)
$script:IconeApp = $null
if ($script:ExeActuel) {
    try {
        $script:IconeApp = [System.Drawing.Icon]::ExtractAssociatedIcon($script:ExeActuel.Chemin)
        $form.Icon = $script:IconeApp
    }
    catch { $script:IconeApp = $null }
}

function Open-PageDepot {
    try {
        Start-Process $urlDepot
    }
    catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Impossible d'ouvrir le navigateur.${nl}${nl}Adresse : $urlDepot",
            "GitHub",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
}

# Lien blanc dans le bandeau d'en-tête
function New-LienEnTete {
    param([string]$Texte, [string]$Infobulle)
    $lien = New-Object System.Windows.Forms.LinkLabel
    $lien.Text = $Texte
    $lien.AutoSize = $true
    $lien.Font = $baseFont
    $lien.BackColor = [System.Drawing.Color]::Transparent
    $lien.LinkColor = [System.Drawing.Color]::White
    $lien.VisitedLinkColor = [System.Drawing.Color]::White
    $lien.ActiveLinkColor = [System.Drawing.Color]::FromArgb(205,225,245)
    $lien.LinkBehavior = 'HoverUnderline'
    $lien.Anchor = 'Top,Right'
    $pnlHeader.Controls.Add($lien)
    $toolTip.SetToolTip($lien, $Infobulle)
    $lien
}

$lnkAPropos = New-LienEnTete "À propos" "Version, auteur et lien vers la page GitHub"
$lnkGitHub  = New-LienEnTete "GitHub" "Ouvrir la page GitHub de l'outil (téléchargements, notes de version)"

# Pendant un traitement CSV, les liens sont atténués et sans effet (un lien désactivé par Windows
# serait dessiné en gris gravé, illisible sur le bandeau bleu)
function Set-LiensEnTeteActifs {
    param([bool]$Actifs)
    foreach ($lien in $lnkAPropos, $lnkGitHub) {
        $lien.LinkColor    = if ($Actifs) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(120,170,220) }
        $lien.LinkBehavior = if ($Actifs) { 'HoverUnderline' } else { 'NeverUnderline' }
    }
}

# Liens alignés à droite du bandeau (appelé à l'affichage, quand la largeur est connue)
function Set-PositionLiensEnTete {
    $y = [int](($pnlHeader.Height - $lnkAPropos.Height) / 2)
    $lnkAPropos.Location = New-Object System.Drawing.Point(($pnlHeader.ClientSize.Width - $lnkAPropos.Width - 20), $y)
    $lnkGitHub.Location  = New-Object System.Drawing.Point(($lnkAPropos.Left - $lnkGitHub.Width - 14), $y)
}

# Fenêtre « À propos » : nom, version, description, auteur, lien vers le dépôt
function New-FenetreAPropos {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "À propos"
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = [System.Drawing.Color]::White
    $dlg.ForeColor = $textColor
    $dlg.Font = $baseFont
    if ($script:IconeApp) { $dlg.Icon = $script:IconeApp }

    $largeur = 400
    $x = 24
    if ($script:IconeApp) {
        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Image = $script:IconeApp.ToBitmap()
        $pic.Size = New-Object System.Drawing.Size(32,32)
        $pic.Location = New-Object System.Drawing.Point(24,24)
        $dlg.Controls.Add($pic)
        $x = 72
    }

    # Libellé à la largeur disponible, avec retour à la ligne automatique
    function Add-Libelle {
        param([string]$Texte, [System.Drawing.Font]$Police, [int]$Haut)
        $l = $largeur - $x - 24
        $h = [System.Windows.Forms.TextRenderer]::MeasureText($Texte, $Police, (New-Object System.Drawing.Size($l, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Texte
        $lbl.Font = $Police
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size($l, $h)
        $lbl.Location = New-Object System.Drawing.Point($x, $Haut)
        $dlg.Controls.Add($lbl)
        $lbl
    }

    $version = if ($script:ExeActuel) { "Version $(Format-Version $script:ExeActuel.Version)" } else { "Version de développement (script .ps1)" }

    $lblNom    = Add-Libelle "Computer Description Tool" (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)) 22
    $lblVer    = Add-Libelle $version $baseFont ($lblNom.Bottom + 2)
    $lblDesc   = Add-Libelle "Modifie la description des postes dans le registre et dans l'Active Directory, à l'unité ou par lot à partir d'un fichier CSV." $baseFont ($lblVer.Bottom + 14)
    $lblAuteur = Add-Libelle "Auteur : vzeol" $baseFont ($lblDesc.Bottom + 10)

    $lien = New-Object System.Windows.Forms.LinkLabel
    $lien.Text = $urlDepot -replace '^https://', ''
    $lien.AutoSize = $true
    $lien.LinkColor = $accentColor
    $lien.VisitedLinkColor = $accentColor
    $lien.ActiveLinkColor = $accentColorHover
    $lien.Location = New-Object System.Drawing.Point($x, ($lblAuteur.Bottom + 4))
    $null = $lien.Add_LinkClicked({ Open-PageDepot })
    $dlg.Controls.Add($lien)

    $btnFermer = New-Object System.Windows.Forms.Button
    $btnFermer.Text = "Fermer"
    $btnFermer.Size = New-Object System.Drawing.Size(100,30)
    Set-ButtonStyle -Button $btnFermer -Primary
    $btnFermer.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnFermer.Location = New-Object System.Drawing.Point(($largeur - 100 - 24), ($lien.Bottom + 24))
    $dlg.Controls.Add($btnFermer)
    $dlg.AcceptButton = $btnFermer
    $dlg.CancelButton = $btnFermer

    $dlg.ClientSize = New-Object System.Drawing.Size($largeur, ($btnFermer.Bottom + 20))
    $dlg
}

function Show-APropos {
    $dlg = New-FenetreAPropos
    try { [void]$dlg.ShowDialog($form) } finally { $dlg.Dispose() }
}

$null = $lnkGitHub.Add_LinkClicked({ if (-not $script:IsCsvRunning) { Open-PageDepot } })
$null = $lnkAPropos.Add_LinkClicked({ if (-not $script:IsCsvRunning) { Show-APropos } })


$null = $form.Add_Shown({

    $margeDroite = 20

    # TextBox PC
    $txtPC.Width = $form.ClientSize.Width - $txtPC.Left - $margeDroite

    # TextBox Description
    $txtDesc.Width = $form.ClientSize.Width - $txtDesc.Left - $margeDroite

    # Zone de résultat rapide
    $txtOut.Width  = $form.ClientSize.Width - $txtOut.Left - $margeDroite

    # Grille de suivi
    $gridResults.Width  = $form.ClientSize.Width - $gridResults.Left - $margeDroite
    $gridResults.Height = $form.ClientSize.Height - $gridResults.Top - 20

    # Liens « GitHub » et « À propos » à droite du bandeau
    Set-PositionLiensEnTete

    # Mise à jour : la fenêtre est d'abord affichée, puis la recherche se fait (5 s maximum)
    $form.Refresh()
    if (Invoke-VerifMiseAJour) {
        $form.Close()
        return
    }

    # Carte des MAC (DHCP -> AD) : construite au lancement, puis rafraîchie avant chaque lot
    if ($script:WolDisponible) {
        Set-Status "Lecture des adresses MAC (DHCP, AD)..."
        $form.Refresh()
        Update-CarteMac
        Set-Status "Prêt"
    }

    if (-not $script:PrerequisOK) {
        [void][System.Windows.Forms.MessageBox]::Show(
            $form,
            $script:MessagePrerequis,
            "Prérequis non remplis",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
})

$null = $form.ShowDialog()

} | Out-Null
