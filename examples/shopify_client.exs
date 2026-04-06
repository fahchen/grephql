# Example: Shopify Admin GraphQL API client
#
# Demonstrates using Grephql with the Shopify Admin schema (10MB).
# Covers products, orders, customers, mutations with input objects.
#
# Enums are auto-handled. Built-in scalars (DateTime, Date, JSON, URL,
# HTML, BigInt, UnsignedInt64) are auto-mapped. Only Shopify-specific
# custom scalars need explicit configuration.
#
# Usage: iex -S mix run examples/shopify_client.exs

defmodule Example.ShopifyClient do
  use Grephql,
    otp_app: :grephql,
    source: "shopify_schema.json",
    scalars: %{
      # Shopify-specific scalars not covered by builtins
      "ARN" => :string,
      "Color" => :string,
      "Decimal" => :string,
      "FormattedString" => :string,
      "Money" => :string,
      "StorefrontID" => :string,
      "UtcOffset" => :string
    }

  # Query: product with nested connections
  defgql(:get_product, ~GQL"""
  query GetProduct($id: ID!) {
    product(id: $id) {
      title
      description
      descriptionHtml
      handle
      productType
      vendor
      status
      createdAt
      updatedAt
      totalInventory
      featuredImage {
        url
        altText
        width
        height
      }
      variants(first: 10) {
        nodes {
          title
          sku
          price
          compareAtPrice
          inventoryQuantity
          selectedOptions {
            name
            value
          }
        }
      }
      collections(first: 5) {
        nodes {
          title
          handle
        }
      }
    }
  }
  """)

  # Query: order with deep nesting
  defgql(:get_order, ~GQL"""
  query GetOrder($id: ID!) {
    order(id: $id) {
      name
      email
      createdAt
      displayFinancialStatus
      displayFulfillmentStatus
      totalPriceSet {
        shopMoney {
          amount
          currencyCode
        }
      }
      subtotalPriceSet {
        shopMoney {
          amount
          currencyCode
        }
      }
      billingAddress {
        firstName
        lastName
        address1
        city
        province
        country
        zip
      }
      lineItems(first: 20) {
        nodes {
          title
          quantity
          originalUnitPriceSet {
            shopMoney {
              amount
              currencyCode
            }
          }
          variant {
            title
            sku
          }
        }
      }
    }
  }
  """)

  # Mutation: product create with input object
  defgql(:create_product, ~GQL"""
  mutation CreateProduct($productInput: ProductCreateInput!, $media: [CreateMediaInput!]) {
    productCreate(product: $productInput, media: $media) {
      product {
        id
        title
        handle
        status
        variants(first: 5) {
          nodes {
            id
            title
            price
          }
        }
      }
      userErrors {
        field
        message
      }
    }
  }
  """)

  # Query: customers list
  defgql(:list_customers, ~GQL"""
  query ListCustomers($first: Int!, $query: String) {
    customers(first: $first, query: $query) {
      nodes {
        id
        firstName
        lastName
        email
        phone
        state
        numberOfOrders
        amountSpent {
          amount
          currencyCode
        }
        defaultAddress {
          address1
          city
          province
          country
        }
      }
    }
  }
  """)
end

IO.puts("Example.ShopifyClient compiled successfully.")
IO.puts("  Queries: get_product, get_order, create_product, list_customers")
