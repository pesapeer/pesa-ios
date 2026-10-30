extension PesaStrings {
    /// French for Canada: `.fr` with Québec usage.
    public static let frCA: PesaStrings = {
        var s = PesaStrings.fr
        s.tag = "fr-CA"
        s.card = "Carte de crédit ou de débit"
        s.email = "Courriel pour votre reçu"
        s.emailPlaceholder = "vous@exemple.ca"
        s.emailInvalid = "Saisissez une adresse courriel."
        return s
    }()
}
