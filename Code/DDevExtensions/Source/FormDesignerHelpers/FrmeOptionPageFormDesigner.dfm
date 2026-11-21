inherited FrameOptionPageFormDesigner: TFrameOptionPageFormDesigner
  Width = 372
  Height = 231
  inherited pnlClient: TPanel
    Width = 372
    Height = 182
    object cbxActive: TCheckBox
      Left = 8
      Top = 8
      Width = 113
      Height = 17
      Caption = '&Active'
      TabOrder = 0
      OnClick = cbxActiveClick
    end
    object cbxLabelMargin: TCheckBox
      Left = 24
      Top = 30
      Width = 340
      Height = 17
      Caption = 'Set TLabel.Margins.Bottom to zero'
      TabOrder = 1
    end
    object chkRemoveExplicitProperties: TCheckBox
      Left = 24
      Top = 51
      Width = 340
      Height = 17
      Caption = 'Do not store the Explicit* properties into the DFM'
      TabOrder = 2
    end
    object chkRemovePixelsPerInchProperties: TCheckBox
      Left = 24
      Top = 72
      Width = 340
      Height = 17
      Caption = 'Do not store TDataModule.PixelsPerInch* property in DFM'
      TabOrder = 3
    end
    object chkRemoveTextHeightProperty: TCheckBox
      Left = 24
      Top = 93
      Width = 340
      Height = 17
      Caption = 'Do not store the TextHeight property into the DFM'
      TabOrder = 4
    end
    object chkFixAlphaControlsPNG: TCheckBox
      Left = 24
      Top = 114
      Width = 340
      Height = 17
      Caption = 'Replace TPNGGraphic (acPNG) with TPngImage'
      TabOrder = 5
    end
    object chkPreferProperPNG: TCheckBox
      Left = 24
      Top = 135
      Width = 340
      Height = 17
      Caption = 'Prefer proper PNG over AlphaControls (registration order)'
      TabOrder = 6
    end
    object chkIDEPngSupport: TCheckBox
      Left = 24
      Top = 156
      Width = 340
      Height = 17
      Caption = 'Provide PNG support in the IDE (bundled pngimage, pre-2009)'
      TabOrder = 7
    end
  end
  inherited pnlDescription: TPanel
    Width = 372
    inherited bvlSplitter: TBevel
      Width = 372
    end
    inherited lblDescription: TLabel
      Width = 212
      Caption = 'Configure the form designer enhancements.'
    end
  end
end
