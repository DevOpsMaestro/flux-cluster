{{/* generate opts for geodata */}}
{{- define "echoip.geolist" }}
- "-a"
- "/geodata/GeoLite2-ASN.mmdb"
- "-c"
- "/geodata/GeoLite2-City.mmdb"
- "-f"
- "/geodata/GeoLite2-Country.mmdb"
{{- end }}