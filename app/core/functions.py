""" Generale useful function """

from enum import StrEnum
from typing import Any

import psycopg
from psycopg.rows import dict_row

from app.core.config import get_settings


def _build_filters(type_ : str | None , sector : str | None) -> tuple[str, tuple[str | None]] :

    filters_types= (type_, type_,sector,sector)
    where_type= """
                    WHERE (%s::text IS NULL OR type = %s) 
                    AND (%s::text IS NULL OR s.name = %s) 
                """ 
    #you can't paste  direclty 
    # psycopg sends the value separately python would paste as text
    # eg : " ... type = %s" % ("stock",) -> type = stock  instead of
    # type == 'stock'

    return where_type,filters_types


def direct_query(sql : str , params:tuple = None ) -> dict[Any]:

    s = get_settings()

    psycopg_connector = psycopg.connect(
        host = s.postgres_host,
        port = s.postgres_port,
        dbname = s.postgres_db,
        user = s.postgres_user,
        password =  s.postgres_password.get_secret_value(),
        row_factory = dict_row, 
    ) 

    with psycopg_connector, psycopg_connector.cursor() as cur: 
        cur.execute(sql,params)
        rows =cur.fetchall()
    
    return rows



def get_enum(countries : bool = False, sectors : bool = False,
            symbols : bool = False, type_ : bool= False,  ) -> dict[str,Any]:


    bools = [countries,sectors,symbols,type_]
    tables = ["countries", "sectors", "symbols", "instrument_types" ]
    selected_tables = [table for table, keep in zip(tables, bools) if keep]

    rows = {}
    for table in selected_tables :
        print(table )

        match table :
            case "symbols":
                sql =""" SELECT symbol FROM instruments """
                resultat_query = direct_query(sql)
                resultat_query=[rq["symbol"] for rq in resultat_query]
            
            case "instrument_types" :
                sql = """ SELECT code FROM instrument_types """  
                resultat_query = direct_query(sql)
                resultat_query=[rq["code"] for rq in resultat_query]
                table="types"
            
            case _ : 
                sql = f"""SELECT name FROM {table} """
                resultat_query = direct_query(sql)
                resultat_query=[rq["name"]for rq in resultat_query] 

        
        rows.update({f"{table}": resultat_query})

    return rows

# 1. The reusable factory function
def make_enum(enum_name: str, key_in_builder: str,) -> type[StrEnum]:
    
    # Fetch the data
    
    data_dict = get_enum(True,True,True,True)
    
    items = data_dict.get(key_in_builder, [])
    
    # Dynamically build the StrEnum
    new_enum = StrEnum(
        enum_name,
        {f"{item.strip().upper()}": item for item in items}
    )
    
    # Inject the case-insensitive logic safely
    def _missing_handler(value):
        try:
            if isinstance(value, str):
                return new_enum[value.strip().upper()]
        except KeyError:
            return None
            
    new_enum._missing_ = _missing_handler
    return new_enum