import type { Provider } from '../database/schema';

/** What each provider stores: plain fields are settings, secret fields are encrypted and never returned. */
export interface FieldSpec {
  key: string;
  label: string;
  secret?: boolean;
  required?: boolean;
  help?: string;
  options?: string[];
}

export interface ProviderSpec {
  provider: Provider;
  title: string;
  /** Where to get the details, shown in the app. */
  help: string;
  fields: FieldSpec[];
}

export const PROVIDERS: ProviderSpec[] = [
  {
    provider: 'whatsapp',
    title: 'WhatsApp (Meta Cloud API)',
    help: 'Create a WhatsApp Business app at developers.facebook.com, add a phone number, and copy the Phone Number ID and a permanent access token. Messages to customers outside a 24-hour chat window must use a template Meta has approved.',
    fields: [
      { key: 'phoneNumberId', label: 'Phone Number ID', required: true },
      { key: 'accessToken', label: 'Access token', secret: true, required: true },
      { key: 'language', label: 'Template language', help: 'e.g. en or en_US (default en)' },
      { key: 'invoiceTemplate', label: 'Invoice template name', help: 'Approved template with 5 body variables: customer, invoice no, amount, balance, business' },
      { key: 'paymentTemplate', label: 'Payment receipt template name', help: 'Approved template with 4 body variables: customer, receipt no, amount, business' },
      { key: 'reminderTemplate', label: 'Payment reminder template name', help: 'Approved template with 3 body variables: customer, amount due, business' },
      { key: 'marketingTemplate', label: 'Marketing template name', help: 'Approved template with 1 body variable: customer' },
      { key: 'apiBase', label: 'API address', help: 'Leave empty (default https://graph.facebook.com/v20.0)' },
    ],
  },
  {
    provider: 'sms',
    title: 'SMS',
    help: 'Twilio: account SID, auth token and a sender number or messaging service. MSG91: auth key, and a DLT-approved flow template (India requires DLT registration).',
    fields: [
      { key: 'gateway', label: 'Gateway', required: true, options: ['twilio', 'msg91'] },
      { key: 'accountSid', label: 'Twilio account SID' },
      { key: 'authToken', label: 'Twilio auth token / MSG91 auth key', secret: true, required: true },
      { key: 'from', label: 'Twilio sender number or messaging service SID' },
      { key: 'msg91TemplateId', label: 'MSG91 flow template ID' },
      { key: 'apiBase', label: 'API address', help: 'Leave empty to use the gateway’s own' },
    ],
  },
  {
    provider: 'einvoice',
    title: 'e-Invoice / e-Way Bill (NIC IRP)',
    help: 'Needs API access from NIC (or a GSP): client ID and secret, the GST portal user name and password, and NIC’s public key. Without them you can still download the e-invoice and e-way bill JSON and upload it on the portal yourself.',
    fields: [
      { key: 'apiBase', label: 'API address', required: true, help: 'Sandbox: https://einv-apisandbox.nic.in  ·  Production: https://einvapi.nic.in (or your GSP’s address)' },
      { key: 'clientId', label: 'Client ID', required: true },
      { key: 'clientSecret', label: 'Client secret', secret: true, required: true },
      { key: 'username', label: 'GST portal user name', required: true },
      { key: 'password', label: 'GST portal password', secret: true, required: true },
      { key: 'publicKey', label: 'NIC public key (PEM)', secret: true, required: true },
      { key: 'gstin', label: 'GSTIN to file under', help: 'Defaults to the company GSTIN' },
    ],
  },
  {
    provider: 'razorpay',
    title: 'Online payments (Razorpay)',
    help: 'In the Razorpay dashboard create API keys and a webhook for the event “Payment Link → paid” pointing at the address shown below, with a secret of your choice.',
    fields: [
      { key: 'keyId', label: 'Key ID', required: true },
      { key: 'keySecret', label: 'Key secret', secret: true, required: true },
      { key: 'webhookSecret', label: 'Webhook secret', secret: true, required: true },
      { key: 'bankAccountId', label: 'Bank account that receives online payments', help: 'Payments are recorded against it' },
      { key: 'apiBase', label: 'API address', help: 'Leave empty (default https://api.razorpay.com)' },
    ],
  },
  {
    provider: 'google_profile',
    title: 'Google Business Profile',
    help: 'Connect the Google account that manages your business listing. Google must have approved this app’s project for the Business Profile API.',
    fields: [],
  },
];

export const PROVIDER_NAMES = PROVIDERS.map((p) => p.provider);

export const specOf = (provider: Provider): ProviderSpec => PROVIDERS.find((p) => p.provider === provider)!;
