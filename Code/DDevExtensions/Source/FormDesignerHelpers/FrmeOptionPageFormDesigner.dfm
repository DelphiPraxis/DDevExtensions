inherited FrameOptionPageFormDesigner: TFrameOptionPageFormDesigner
  Width = 372
  Height = 188
  inherited pnlClient: TPanel
    Width = 372
    Height = 139
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
      Top = 31
      Width = 313
      Height = 17
      Caption = 'Set TLabel.Margins.Bottom to zero'
      TabOrder = 1
    end
    object chkRemoveExplicitProperties: TCheckBox
      Left = 24
      Top = 54
      Width = 241
      Height = 17
      Caption = 'Don'#39't store "Explicit" properties in DFM'
      TabOrder = 2
    end
    object chkRemovePixelsPerInchProperties: TCheckBox
      Left = 24
      Top = 77
      Width = 330
      Height = 17
      Caption = 'Don'#39't store "TDataModule.PixelsPerInch" property in DFM'
      TabOrder = 4
    end
    object chkRemoveTextHeightProperty: TCheckBox
      Left = 24
      Top = 100
      Width = 330
      Height = 17
      Caption = 'Do not store the TForm.TextHeight property into the DFM'
      TabOrder = 3
    end
  end
  inherited pnlDescription: TPanel
    Width = 372
    inherited bvlSplitter: TBevel
      Width = 372
    end
    inherited lblDescription: TLabel
      Width = 234
      Caption = 'Configure the form designer enhancements.'
    end
  end
end
