import { useState } from 'react';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '../components/ui/card';
import { Button } from '../components/ui/button';
import { Badge } from '../components/ui/badge';
import { executeGraphQL } from '../api/graphqlClient';

interface AccountNode {
  Id: string;
  Name?: {
    value: string;
  };
}

interface GraphQLAccountResponse {
  uiapi?: {
    query?: {
      Account?: {
        edges?: Array<{
          node: AccountNode;
        }>;
      };
    };
  };
}

export default function Home() {
  const [count, setCount] = useState(0);
  const [accounts, setAccounts] = useState<AccountNode[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchAccounts = async () => {
    setLoading(true);
    setError(null);
    try {
      const query = `
        query getAccounts {
          uiapi {
            query {
              Account(first: 5) {
                edges {
                  node {
                    Id
                    Name {
                      value
                    }
                  }
                }
              }
            }
          }
        }
      `;
      const response = await executeGraphQL<GraphQLAccountResponse, void>(query);
      const fetched = response?.uiapi?.query?.Account?.edges?.map(edge => edge.node) || [];
      setAccounts(fetched);
    } catch (err: unknown) {
      console.error('GraphQL Query Error:', err);
      setError(err instanceof Error ? err.message : 'Failed to query Salesforce GraphQL endpoint');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-10 space-y-8">
      {/* Hero Header */}
      <div className="text-center space-y-3">
        <div className="flex justify-center items-center gap-2">
          <Badge variant="outline" className="px-3 py-1 text-sm font-semibold border-blue-500 text-blue-600 bg-blue-50">
            Salesforce Multi-Framework
          </Badge>
          <Badge variant="outline" className="px-3 py-1 text-sm font-semibold border-green-500 text-green-600 bg-green-50">
            UIBundle Native Runtime
          </Badge>
        </div>
        <h1 className="text-4xl font-extrabold tracking-tight text-gray-900 sm:text-5xl">
          React inside Experience Cloud
        </h1>
        <p className="text-lg text-gray-600 max-w-2xl mx-auto">
          Proof of Concept demonstrating native React 19 + TypeScript + Tailwind running directly on Salesforce with GraphQL UI API integration.
        </p>
      </div>

      {/* Grid of POC Capabilities */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Capability 1: React State Management */}
        <Card className="shadow-sm border border-gray-200">
          <CardHeader>
            <CardTitle>1. Interactive React State</CardTitle>
            <CardDescription>
              Verify reactive re-rendering and hook lifecycle inside the Salesforce container.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="p-4 bg-gray-50 rounded-lg flex items-center justify-between">
              <span className="text-gray-700 font-medium">Counter Value:</span>
              <span className="text-2xl font-bold text-blue-600">{count}</span>
            </div>
            <div className="flex gap-3">
              <Button onClick={() => setCount(c => c + 1)}>
                Increment (+1)
              </Button>
              <Button variant="outline" onClick={() => setCount(0)}>
                Reset
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Capability 2: Salesforce UI API GraphQL Query */}
        <Card className="shadow-sm border border-gray-200">
          <CardHeader>
            <CardTitle>2. Native GraphQL Data SDK</CardTitle>
            <CardDescription>
              Query live Salesforce records via <code>@salesforce/platform-sdk</code> without custom Apex or OAuth.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button onClick={fetchAccounts} disabled={loading} className="w-full">
              {loading ? 'Querying GraphQL...' : 'Query Accounts from Salesforce'}
            </Button>

            {error && (
              <div className="p-3 bg-red-50 text-red-700 rounded-lg text-xs border border-red-200">
                <strong>Error:</strong> {error}
              </div>
            )}

            {accounts.length > 0 && (
              <div className="space-y-2">
                <p className="text-xs font-semibold uppercase tracking-wider text-gray-500">Returned Accounts:</p>
                <ul className="divide-y divide-gray-100 bg-gray-50 rounded-lg p-2 text-sm">
                  {accounts.map(acc => (
                    <li key={acc.Id} className="py-1.5 px-2 flex justify-between">
                      <span className="font-medium text-gray-900">{acc.Name?.value || 'Unnamed'}</span>
                      <span className="text-xs text-gray-400 font-mono">{acc.Id}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Info Section */}
      <Card className="bg-slate-50 border border-slate-200">
        <CardHeader>
          <CardTitle className="text-sm font-semibold text-slate-700">POC Architecture Overview</CardTitle>
        </CardHeader>
        <CardContent className="text-xs text-slate-600 space-y-1">
          <p>• <strong>Metadata Type:</strong> <code>UIBundle</code> (Native Salesforce Artifact)</p>
          <p>• <strong>Frontend Stack:</strong> React 19, Vite, TypeScript, Tailwind CSS, Radix UI</p>
          <p>• <strong>Data Layer:</strong> Salesforce Data SDK querying UI API GraphQL directly</p>
          <p>• <strong>Authentication:</strong> Inherited from Salesforce session automatically</p>
        </CardContent>
      </Card>
    </div>
  );
}
