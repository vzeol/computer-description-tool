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

# Champ Desc
$txtDesc = New-Object System.Windows.Forms.TextBox
$txtDesc.Location = "130,107"
$txtDesc.Width = 180
$txtDesc.Font = $baseFont
$form.Controls.Add($txtDesc)
$txtDesc.Anchor = 'Top,Left,Right'

# Saut de ligne standard Windows (WinForms)
$nl = [Environment]::NewLine

#Flag bouton annuler
$script:IsCsvRunning = $false
$script:CancelRequested = $false


############################################
# Creation bouton
############################################

# Tailles et positions des boutons
$btnWidth  = 130
$btnHeight = 30
$btnLeftX  = 20
$btnGap    = 10
$btnRightX = $btnLeftX + $btnWidth + $btnGap

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
$lblGrid.Text = "Suivi du traitement :"
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
$gridResults.MultiSelect = $false
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
$gridResults.Columns['colEtat'].FillWeight = 55
$form.Controls.Add($gridResults)

# Couleurs de statut (lignes du suivi CSV)
$colorOkBack   = [System.Drawing.Color]::FromArgb(223,246,221)
$colorOkFore   = [System.Drawing.Color]::FromArgb(30,90,30)
$colorKoBack   = [System.Drawing.Color]::FromArgb(253,231,230)
$colorKoFore   = [System.Drawing.Color]::FromArgb(140,20,20)

function Add-SuiviRow {
    param([string]$PC, [string]$Desc, [string]$Etat)

    $rowIndex = $gridResults.Rows.Add($PC, $Desc, $Etat)
    $row = $gridResults.Rows[$rowIndex]

    if ($Etat -eq "OK") {
        $row.DefaultCellStyle.BackColor = $colorOkBack
        $row.DefaultCellStyle.ForeColor = $colorOkFore
    }
    else {
        $row.DefaultCellStyle.BackColor = $colorKoBack
        $row.DefaultCellStyle.ForeColor = $colorKoFore
    }

    # La grille sélectionne d'office la 1re ligne : le bleu de sélection masquerait sa couleur d'état
    $gridResults.ClearSelection()

    $gridResults.FirstDisplayedScrollingRowIndex = $rowIndex
    [System.Windows.Forms.Application]::DoEvents()
}

############################################
# Action Tooltips
############################################

# Tooltips
$toolTip.SetToolTip($txtPC,   "Nom du poste tel qu'il apparaît dans l'Active Directory")
$toolTip.SetToolTip($txtDesc, "Description à appliquer au poste")

$toolTip.SetToolTip($btnTest,  "Teste l'accès (Ping + ADMIN$) et lit la description actuelle")
$toolTip.SetToolTip($btnApply,"Applique la description dans le registre et l'AD")
$toolTip.SetToolTip($btnHelp, "Affiche l'aide sur le format CSV attendu")
$toolTip.SetToolTip($btnCSV,  "Traite un fichier CSV et suit la progression en temps réel")

############################################
# Fonction
############################################

#Fonction Désactiver/Activer l'ui pendant traitement
function Disable-UI {
    $btnTest.Enabled  = $false
    $btnApply.Enabled = $false
    $btnHelp.Enabled  = $false
    # $btnCSV.Enabled   = $false
}

function Enable-UI {
    $btnTest.Enabled  = $true
    $btnApply.Enabled = $true
    $btnHelp.Enabled  = $true
    $btnCSV.Enabled   = $true
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
- Ligne sans PC ou sans description : signalée « LIGNE INVALIDE », non appliquée",
"Aide – Format CSV",
[System.Windows.Forms.MessageBoxButtons]::OK,
[System.Windows.Forms.MessageBoxIcon]::Information
    )
})

# Action Verifier le PC
$null = $btnTest.Add_Click({
    $pc = $txtPC.Text.Trim()

    if ($pc -eq "") {
        $txtOut.Text = "Aucun PC spécifié."
        return
    }

    try {
        if (!(Test-Connection -ComputerName $pc -Count 1 -Quiet)) {
            $txtOut.Text = "Ping K.O : PC hors ligne."
            return
        }

        if (!(Test-Path "\\$pc\ADMIN$")) {
            $txtOut.Text = "ADMIN$ K.O : pas d'accès administrateur."
            return
        }

        $r=[Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$pc)
        $k=$r.OpenSubKey('SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters',$false)
        $val=$k.GetValue('srvcomment')
        $k.Close()

        $kOS = $r.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion',$false)
        $product = $kOS.GetValue('ProductName')
        $version = $kOS.GetValue('DisplayVersion')
        if (-not $version) {
        $version = $kOS.GetValue('ReleaseId')
                            }

        $kOS.Close()


        $txtOut.Text =
        "OK : PC joignable." + $nl +
        "Description actuelle : $val" + $nl +
        "OS : $product $version"
    }
    catch {
        $txtOut.Text = "Erreur : $($_.Exception.Message)"
    }
})

# Action Appliquer
$null = $btnApply.Add_Click({
    try {
        $pc = $txtPC.Text
        $desc = $txtDesc.Text

        if ($pc -eq "" -or $desc -eq "") {
            $txtOut.Text = "Champs incomplets."
            return
        }

        # Écriture registre
        $r=[Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$pc)
        $k=$r.OpenSubKey('SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters',$true)
        $k.SetValue('srvcomment',$desc,'String')
        $k.Close()

        # Mise à jour description AD
        $null = Import-Module ActiveDirectory -ErrorAction Stop
        Set-ADComputer -Identity $pc -Description $desc

        # Lecture pour validation
        $k2=$r.OpenSubKey('SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters',$false)
        $val=$k2.GetValue('srvcomment')
        $k2.Close()

        $txtOut.Text = "Description appliquée : Registre = '$val' / AD = OK"
    }
    catch {
        $txtOut.Text = "Erreur : $($_.Exception.Message)"
    }
})

# Action Traiter CSV
$null = $btnCSV.Add_Click({

    # Si déjà en cours → on demande l'annulation
    if ($script:IsCsvRunning) {
        $script:CancelRequested = $true
        Set-Status "Annulation demandée..."
        return
    }

    # Fenêtre de sélection CSV
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Fichier CSV (*.csv)|*.csv"
    $dialog.Title = "Sélectionner un fichier CSV"

    $result = $dialog.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return }

    # Confirmation avant traitement
    $nomFichier = [System.IO.Path]::GetFileName($dialog.FileName)
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Le fichier ""$nomFichier"" va être utilisé pour modifier les postes listés.${nl}${nl}Êtes-vous sûr de vouloir continuer ?",
        "Confirmation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:IsCsvRunning = $true
    $script:CancelRequested = $false
    Set-CsvButtonMode $true

    Disable-UI
    Set-Status "Traitement du CSV..."

    $progressBar.Visible = $true
    $progressBar.Value = 0

    $gridResults.Rows.Clear()
    $txtOut.Text = "Traitement en cours — suivi ci-dessous."

    try {

        $null = Import-Module ActiveDirectory -ErrorAction Stop
        $path = $dialog.FileName

        # @() : sous PowerShell 5.1, un CSV d'une seule ligne ne renvoie pas de tableau (pas de .Count)
        $data = @(Import-Csv -Path $path -Delimiter ";")

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

        $resultats = @()
        $nbOK = 0
        $nbKO = 0
        $total = $data.Count
        $index = 0

        foreach ($line in $data) {

            # === PATCH ANNULER ===
            if ($script:CancelRequested) {
                Set-Status "Traitement annulé ($index / $total)"
                break
            }

            $pc   = "$($line.PC)".Trim()
            $desc = "$($line.Description)".Trim()
            $etat = "OK"

            if ($pc -eq "" -or $desc -eq "") {
                # PC ou description manquant : ligne signalée, rien n'est modifié
                $etat = "LIGNE INVALIDE"
            }
            elseif (!(Test-Connection -ComputerName $pc -Count 1 -Quiet)) {
                $etat = "PING K.O"
            }
            elseif (!(Test-Path "\\$pc\ADMIN$")) {
                $etat = "ADMIN$ K.O"
            }
            else {
                try {
                    $r=[Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$pc)
                    $k=$r.OpenSubKey('SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters',$true)
                    $k.SetValue('srvcomment',$desc,'String')
                    $k.Close()

                    Set-ADComputer -Identity $pc -Description $desc
                }
                catch {
                    $etat = "ERREUR"
                }
            }

            if ($etat -eq "OK") { $nbOK++ } else { $nbKO++ }

            $resultats += [PSCustomObject]@{
                PC = $pc
                Description = $desc
                Etat = $etat
            }

            Add-SuiviRow -PC $pc -Desc $desc -Etat $etat

            $index++
            $progressBar.Value = [Math]::Min(100, [int](($index / $total) * 100))
            Set-Status "Traitement du CSV... ($index / $total)"

            [System.Windows.Forms.Application]::DoEvents()
        }

        if (-not $script:CancelRequested) {
            Set-Status "Traitement terminé"
        }

        $txtOut.Text = "Résumé : OK = $nbOK | Échecs = $nbKO"

        $genererRapport = [System.Windows.Forms.MessageBox]::Show(
            "Voulez-vous générer le rapport CSV du traitement ?",
            "Rapport",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($genererRapport -eq [System.Windows.Forms.DialogResult]::Yes) {
            $date = Get-Date -Format "yyyy-MM-dd_HH-mm"
            $rep = $path -replace "\.csv$", "_RAPPORT_$date.csv"
            $resultats | Export-Csv -Path $rep -Delimiter ";" -NoTypeInformation -Encoding UTF8
            $txtOut.Text += $nl + "Rapport exporté : $rep"
        }
    }
    catch {
        Set-Status "Erreur CSV"
        $txtOut.Text = "Erreur CSV : $($_.Exception.Message)"
    }
    finally {
        Enable-UI
        $progressBar.Value = 0
        $progressBar.Visible = $false

        $script:IsCsvRunning = $false
        $script:CancelRequested = $false
        Set-CsvButtonMode $false

        Set-Status "Prêt"
    }
})


############################################
# Rappel compte / domaine + blocage si prérequis non remplis
############################################

$etatDomaine = if (-not $prerequis.Domaine) { "NON" }
               elseif ($prerequis.EstDC) { "OK ($($prerequis.NomDomaine), contrôleur de domaine)" }
               else { "OK ($($prerequis.NomDomaine))" }
$etatAdmin   = if ($prerequis.Admin) { "OK" } else { "NON" }
$etatModule  = if ($prerequis.ModuleAD) { "OK" } else { "NON" }

$detailPrerequis =
    "Compte utilisé : $($prerequis.Compte)" + $nl + $nl +
    "Poste membre du domaine : $etatDomaine" + $nl +
    "Compte administrateur du domaine : $etatAdmin" + $nl +
    "Module ActiveDirectory (RSAT) : $etatModule"

$lblSession.Text = if (-not $prerequis.Domaine) { "$($prerequis.Compte) · hors domaine" }
                   elseif ($prerequis.EstDC) { "$($prerequis.Compte) · $($prerequis.NomDomaine) (DC)" }
                   else { "$($prerequis.Compte) · $($prerequis.NomDomaine)" }
$lblSession.ToolTipText = $detailPrerequis

if (-not $script:PrerequisOK) {
    $btnTest.Enabled  = $false
    $btnApply.Enabled = $false
    $btnCSV.Enabled   = $false
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

$null = $form.Topmost = $true

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

    # Mise à jour : la fenêtre est d'abord affichée, puis la recherche se fait (5 s maximum)
    $form.Refresh()
    if (Invoke-VerifMiseAJour) {
        $form.Close()
        return
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
