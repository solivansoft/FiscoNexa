unit Application.CompanyRegistry;

interface

type
  TCompanyRegistryData = record
    Cnpj, State, LegalName, TradeName, Json: string;
    Available: Boolean;
  end;

  ICompanyRegistry = interface
    ['{7BD81507-850A-43EE-BB96-75397525321A}']
    function Lookup(const ACnpj: string): TCompanyRegistryData;
  end;

implementation

end.
