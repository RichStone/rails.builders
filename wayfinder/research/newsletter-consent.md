# Newsletter Consent for Verified Rails Builders Registrants

- Researched: 2026-08-09
- Scope: adding a verified `rails.builders` Registrant to the Loop Labs email newsletter
- Assumption: the relevant controller is established in Germany, or the processing and email campaign are otherwise subject to the GDPR and German rules on email advertising. The controller identity and territorial analysis still need counsel confirmation.
- This is product research, not legal advice.

## Decision-relevant answer

Email verification is not newsletter consent. It proves access to an email account; it does not show a freely given, specific, informed, affirmative choice to receive Loop Labs marketing. A Registrant should therefore **not** be added to the Loop Labs newsletter merely because their `rails.builders` email is verified.

The defensible product rule is:

```text
subscribe only when registration_email_verified
           AND newsletter_consent_confirmed
```

The newsletter choice should be optional, separate from registration, unchecked by default, and followed by a newsletter-specific confirmation step. A complete privacy notice is also required, but disclosure in that notice alone is not consent.

## Authoritative requirements and regulator positions

### 1. Prior consent is the default rule for marketing email

EU ePrivacy law permits email used for direct marketing only for users who have given prior consent. It has a narrow existing-customer exception where the same person obtained the address in the context of a sale and markets its own similar products or services, with a clear, free and easy opportunity to object both when the address is collected and in every message ([ePrivacy Directive, Article 13(1)-(2)](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A02002L0058-20091219)).

Germany implements the channel rule in § 7 UWG. Marketing by electronic mail without the addressee's prior express consent is an unacceptable nuisance. The § 7(3) exception applies only if all four conditions are met: the business obtained the address from a customer in connection with a sale; uses it for its own similar goods or services; the customer has not objected; and the customer is clearly told at collection and every use that they may object without more than basic transmission costs ([UWG § 7(2) no. 2 and § 7(3)](https://www.gesetze-im-internet.de/uwg_2004/__7.html)).

On the supplied facts, a verified registration does not establish a sale, an existing-customer relationship, the same sender, or similarity between Rails Builders and everything promoted in the Loop Labs newsletter. The German supervisory authorities state that, without all § 7(3) conditions, using an email address for advertising generally requires consent. They also state that a contact channel prohibited by § 7 UWG cannot be rescued as a GDPR legitimate interest ([DSK direct-marketing guidance, §§ 1.4 and 1.4.1, pp. 6-7](https://www.datenschutzkonferenz-online.de/media/oh/OH-Werbung_Februar%202022_final.pdf)).

GDPR Recital 47 says direct marketing *may* be a legitimate interest, but that general statement does not displace the ePrivacy/UWG rule specific to email. For this proposed flow, consent under GDPR Article 6(1)(a) is the risk-controlled basis unless counsel confirms that every part of the customer exception applies ([GDPR, Article 6 and Recital 47](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)).

### 2. Verification, notice, silence and a preselected choice are not consent

GDPR consent must be freely given, specific, informed and unambiguous, expressed by a statement or clear affirmative action. The controller must be able to demonstrate it; a written request mixed with other matters must be clearly distinguishable and in clear, plain language; and conditioning a service on unnecessary processing weighs against freedom of consent ([GDPR, Articles 4(11) and 7](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)).

The EDPB draws the relevant product consequences:

- consent is invalid where there is no genuine choice or refusal causes detriment (paragraphs 13-14);
- separate purposes require granular choices rather than a bundle (paragraphs 42-44);
- the request must be separate and distinct, not merely a paragraph in terms (paragraph 71); and
- the data subject must be told at least the controller's identity, each purpose, the type of data used, the withdrawal right, relevant automated decision-making, and certain transfer risks (paragraph 64) ([EDPB Guidelines 05/2020 on consent](https://www.edpb.europa.eu/system/files/documents/files/file1/edpb_guidelines_202005_consent_en.pdf)).

The CJEU has also held that a pre-ticked checkbox is not valid consent because it does not demonstrate active behaviour. Its reasoning expressly applies GDPR Articles 4(11) and 6(1)(a), even though the immediate dispute concerned cookies ([CJEU, *Planet49*, C-673/17, paragraphs 54-63 and operative part](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A62017CJ0673)).

Consequently, clicking a link that the Registrant must click to verify registration cannot by itself signify optional newsletter consent. A privacy-policy statement saying that verified Registrants are added automatically is notice of the controller's intended conduct, not the Registrant's affirmative agreement.

For email advertising specifically, the BGH requires the addressee to know that the declaration is consent and to be able to identify the products or services and the companies it covers ([BGH, 14 March 2017, VI ZR 721/15](https://juris.bundesgerichtshof.de/cgi-bin/bgh_notp/document.py?Art=en&Blank=1&Datum=2017-3&Gericht=bgh&Seite=3&Sort=1&anz=266&nr=41633&pos=105)). The DSK translates that into disclosure of the advertising channel, the products or services being promoted, and the advertising companies ([DSK guidance, § 3.1, pp. 10-11](https://www.datenschutzkonferenz-online.de/media/oh/OH-Werbung_Februar%202022_final.pdf)). “Marketing” alone is too vague for this flow.

### 3. Consent information and the privacy notice are related but separate

When data are collected from the Registrant, GDPR Article 13 requires the following information at collection, in a concise, transparent, intelligible and accessible form under Article 12:

- controller identity and contact details, and the DPO where applicable;
- newsletter purpose and legal basis;
- recipients or categories of recipients, including the newsletter platform category;
- applicable third-country transfers and safeguards;
- retention period or criteria;
- access, correction, deletion, restriction, objection and portability rights as applicable;
- the right to withdraw consent without affecting prior lawful processing;
- the right to complain to a supervisory authority;
- whether providing the data is required and the consequences of not providing it; and
- relevant automated decision-making information ([GDPR, Articles 12 and 13](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)).

If `rails.builders` and Loop Labs are separate controllers and Loop Labs receives rather than directly collects the address, Article 14 applies to Loop Labs, including source and data-category information, by the earlier applicable deadline: a reasonable period capped at one month, the first communication, or the first disclosure to another recipient, unless an Article 14(5) exception applies (including that the Registrant already has the information). The EDPB also says all controllers intending to rely on the original consent should be named; processors need not be named in the short consent request, although recipients or recipient categories belong in the Article 13/14 notice (EDPB Guidelines 05/2020, paragraph 65; [GDPR, Article 14](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)).

The EDPB treats informed consent and Article 13/14 transparency as distinct duties. They may use a layered, integrated presentation, and the longer notice may contain some of the detail, but the electronic consent request must remain separate and distinct (paragraphs 71-72 of the [EDPB consent guidelines](https://www.edpb.europa.eu/system/files/documents/files/file1/edpb_guidelines_202005_consent_en.pdf)). Thus:

> A linked, complete privacy notice can help satisfy the information duties. It cannot replace the optional affirmative newsletter choice required by GDPR consent and UWG § 7.

### 4. The controller must retain evidence; German guidance expects double opt-in

GDPR Article 7(1) puts the burden of demonstrating consent on the controller. The EDPB says the GDPR does not prescribe one proof method, but the controller should be able to show how and when consent was obtained, the information shown at that time, and that the workflow met the validity conditions. Proof should last while the processing continues and afterward only as long as necessary for a legal obligation or legal claims (EDPB Guidelines 05/2020, paragraphs 103-108; [GDPR, Articles 5(2) and 7(1)](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)).

The statutes do not literally prescribe a “double opt-in” procedure. Nevertheless, the DSK says double opt-in is called for to verify an electronically expressed choice, that IP storage alone is insufficient, and that the actual statement and confirmation must be fully reproducible ([DSK guidance, § 3.3, pp. 11-12](https://www.datenschutzkonferenz-online.de/media/oh/OH-Werbung_Februar%202022_final.pdf)). The federal data-protection authority likewise instructs newsletter operators to use double opt-in for advertising newsletters ([BfDI, “Newsletter-Bestellung auf Webseiten”](https://www.bfdi.bund.de/DE/Fachthemen/Inhalte/Telemedien/Newsletter.html)).

The BGH held that each person's concrete electronic declaration must be completely documented and capable of being reproduced. It explained that an unchecked form checkbox followed by confirmation from the relevant email address generally documents express consent to email advertising at that address, while also warning that double opt-in is not irrebuttable proof and cannot establish consent for a different channel such as a telephone number ([BGH, 10 February 2011, I ZR 164/09, paragraphs 30-39](https://juris.bundesgerichtshof.de/cgi-bin/bgh_notp/document.py?Art=en&Datum=2011-2&Gericht=bgh&Sort=1024&anz=294&pos=30)). Double opt-in is therefore a strong German regulator and litigation-risk requirement for this product, not a substitute for a valid first consent.

### 5. Withdrawal and objection must stop newsletter use

The person may withdraw consent at any time, must be told about that right before consenting, and withdrawal must be as easy as giving consent. Withdrawal does not invalidate earlier lawful processing ([GDPR, Article 7(3)](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)). For processing for direct marketing, the person also has an unconditional right to object at any time; after objection, the data may no longer be processed for that purpose, and this right must be brought to their attention clearly and separately no later than the first communication ([GDPR, Article 21(2)-(4)](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)). German law additionally prohibits a marketing message that lacks a valid, low-cost address for requesting that messages cease ([UWG § 7(2) no. 3(c)](https://www.gesetze-im-internet.de/uwg_2004/__7.html)).

The EDPB says electronically given consent must in practice be withdrawable through an equally easy electronic interface, without detriment, and that the consent-based processing must stop. Data must be deleted if no other legal basis justifies keeping it (EDPB Guidelines 05/2020, paragraphs 113-119). The DSK distinguishes removal from the advertising database from limited retention of consent evidence and points to the regular German three-year regulatory and civil limitation periods, while requiring disclosure of that post-withdrawal proof retention ([DSK guidance, § 3.7, pp. 14-15](https://www.datenschutzkonferenz-online.de/media/oh/OH-Werbung_Februar%202022_final.pdf)). Counsel should set the exact retention event, term and legal basis rather than treating “three years” as an automatic deletion formula.

## Product recommendations based on those requirements

These are implementation choices to control legal risk, not statements that every UI detail is expressly written in a statute.

1. **Keep registration and newsletter choice independent.** Registration and its email verification must succeed when the newsletter box is left empty. Do not preselect the box and do not describe newsletter subscription as acceptance of the privacy policy or terms.
2. **Use a concrete inline opt-in.** A suitable pattern for counsel to finalize is: “Yes, email me the Loop Labs newsletter from **[full legal entity]** about **[specific topics/products/services]**. I can unsubscribe at any time. [Newsletter privacy information].” State the sender's legal identity, not merely a brand. Frequency is useful expectation-setting even though the cited provisions do not make a fixed cadence an express minimum.
3. **Use a newsletter-specific double opt-in.** After the optional checkbox is selected, send an advertising-free confirmation message whose link clearly confirms the Loop Labs newsletter. Only create/activate the ClickFunnels subscription after that confirmation. A single email may carry both registration and newsletter actions, but the actions and consequences should be separate; the required registration-verification click should not also confirm the optional newsletter.
4. **Record the evidence, not just the result.** Retain the Registrant/subscriber identifier and email, consent and confirmation timestamps, source form, exact consent-text version, controller and stated subject scope, privacy-notice version presented, confirmation delivery/token result, and later withdrawal/objection and suppression timestamps. An IP address alone is insufficient; do not collect extra proof data without a necessity assessment.
5. **Make stopping immediate and easy.** Put a functioning one-click unsubscribe or equivalently easy electronic control in every newsletter, identify the sender, honor withdrawal/objection across Rails Builders, Loop Labs and ClickFunnels without further marketing sends, and retain only the minimal evidence/suppression data justified by the retention policy.
6. **Update the privacy notice before collection.** Add a distinct newsletter section containing the Article 13 information above, the double-opt-in and unconfirmed-request retention rules, the ClickFunnels/other recipient category and transfer position, withdrawal mechanics, and the separate post-withdrawal proof/suppression retention rule. Link it beside the checkbox and in the confirmation message; do not rely on a site-wide policy link hidden in the footer.
7. **Do not enable open/click tracking by default.** The BfDI treats tracking pixels and similar newsletter telemetry as a separate consent question under ePrivacy/TDDDG. If Loop Labs wants per-recipient tracking, resolve that data flow and consent separately rather than folding it silently into newsletter consent ([BfDI newsletter guidance](https://www.bfdi.bund.de/DE/Fachthemen/Inhalte/Telemedien/Newsletter.html)).

## Questions requiring counsel before implementation

- Which legal person is the controller behind `rails.builders` and which is the sender/controller behind “Loop Labs”? Are they the same controller, separate controllers, joint controllers, or a controller and processor?
- Does German UWG apply to every intended recipient and campaign? The recommended flow assumes it does; counsel should confirm territorial rules for recipients elsewhere.
- Is there any real sale/customer relationship on which § 7(3) could operate, and would a Loop Labs newsletter be the same legal person's advertising for its own similar services? Do not rely on the exception without a fact-specific answer covering all four conditions.
- What exact newsletter topics, entities, processors, transfers, tracking features and retention periods must the final consent copy and privacy notice name?
- What exact limitation calculation and legal basis should govern post-withdrawal consent evidence and suppression data?
- If minors may register, what age/parental-consent design is required under GDPR Article 8 and applicable German law?

## Sources

Only primary law, courts, and official EU/German regulator materials were used:

- [Regulation (EU) 2016/679 (GDPR), EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679)
- [Directive 2002/58/EC, consolidated Article 13, EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A02002L0058-20091219)
- [German UWG § 7, Federal Ministry of Justice/Bundesamt für Justiz](https://www.gesetze-im-internet.de/uwg_2004/__7.html)
- [EDPB Guidelines 05/2020 on consent, version 1.1](https://www.edpb.europa.eu/system/files/documents/files/file1/edpb_guidelines_202005_consent_en.pdf)
- [German DSK direct-marketing guidance, February 2022](https://www.datenschutzkonferenz-online.de/media/oh/OH-Werbung_Februar%202022_final.pdf)
- [BfDI newsletter guidance](https://www.bfdi.bund.de/DE/Fachthemen/Inhalte/Telemedien/Newsletter.html)
- [CJEU, *Planet49*, C-673/17](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A62017CJ0673)
- [BGH, VI ZR 721/15](https://juris.bundesgerichtshof.de/cgi-bin/bgh_notp/document.py?Art=en&Blank=1&Datum=2017-3&Gericht=bgh&Seite=3&Sort=1&anz=266&nr=41633&pos=105)
- [BGH, I ZR 164/09](https://juris.bundesgerichtshof.de/cgi-bin/bgh_notp/document.py?Art=en&Datum=2011-2&Gericht=bgh&Sort=1024&anz=294&pos=30)
